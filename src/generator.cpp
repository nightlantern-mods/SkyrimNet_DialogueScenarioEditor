#include "generator.h"

#include "skyrimnet/PublicAPI.h"

#include <algorithm>
#include <atomic>
#include <charconv>
#include <filesystem>
#include <format>
#include <fstream>
#include <map>
#include <memory>
#include <set>

#include <nlohmann/json.hpp>

namespace
{
    using json = nlohmann::json;

    constexpr const char* kVariant = "dialogue_scenario_writer";
    constexpr const char* kPlanPrompt = "dse_scenario_plan";
    constexpr const char* kColumnPrompt = "dse_scenario_column";
    constexpr const char* kEvent = "DSE_Gen";
    constexpr int         kMaxColumns = 10;
    constexpr int         kMaxCast = 3;
    constexpr int         kMaxLines = 10;
    constexpr int         kMaxPeople = 10;
    constexpr std::size_t kMaxRelations = 24;

    bool              g_api = false;
    std::atomic<bool> g_busy = false;

    struct Person
    {
        RE::FormID  ref = 0;  // the actor (reference) when one was found, else the base
        std::string name;
        bool        player = false;
    };

    struct Job
    {
        Person              writer;
        std::vector<Person> people;
        int                 columns = 1;
        std::string         theme;
        std::string         language;
        json                tags = json::array();       // [{tag, meaning}]
        json                soloTags = json::array();   // [tag]
        json                relations = json::array();  // [text]
        std::string         title;
        std::string         plot;
        json                outline = json::array();  // the plan's columns, cleaned
        json                written = json::array();  // columns written so far, for the next prompt
        json                result = json::array();   // columns for the page
        int                 next = 0;                 // the column being written
        bool                retried = false;
    };

    std::string Dump(const json& a_json)
    {
        return a_json.dump(-1, ' ', false, json::error_handler_t::replace);
    }

    // To Papyrus (game thread), which passes it to the page.
    void Send(json a_message)
    {
        std::string text = Dump(a_message);
        SKSE::GetTaskInterface()->AddTask([text = std::move(text)]() {
            SKSE::ModCallbackEvent event{ RE::BSFixedString(kEvent), RE::BSFixedString(text.c_str()), 0.0f, nullptr };
            SKSE::GetModCallbackEventSource()->SendEvent(&event);
        });
    }

    void Fail(const std::string& a_code, const std::string& a_detail = {})
    {
        logger::warn("Generate: {} {}", a_code, a_detail);
        g_busy = false;
        Send({ { "type", "error" }, { "code", a_code }, { "detail", a_detail } });
    }

    void Progress(int a_step, int a_total, const std::string& a_what)
    {
        Send({ { "type", "progress" }, { "step", a_step }, { "total", a_total }, { "what", a_what } });
    }

    // ---- who is who ----

    bool IsPlayerWord(const std::string& a_spec)
    {
        return a_spec == "player" || a_spec == "{player}" || a_spec == "\xE3\x83\x97\xE3\x83\xAC\xE3\x82\xA4\xE3\x83\xA4\xE3\x83\xBC" ||
               a_spec == "{\xE3\x83\x97\xE3\x83\xAC\xE3\x82\xA4\xE3\x83\xA4\xE3\x83\xBC}";
    }

    // "0x1A2B3|Skyrim.esm" (the page's form for an NPC: local base id and plugin) -> the base form.
    RE::TESNPC* LookUpBase(const std::string& a_spec)
    {
        const auto bar = a_spec.find('|');
        if (bar == std::string::npos) {
            return nullptr;
        }
        std::string_view hex(a_spec.data(), bar);
        if (hex.starts_with("0x") || hex.starts_with("0X")) {
            hex.remove_prefix(2);
        }
        RE::FormID local = 0;
        std::from_chars(hex.data(), hex.data() + hex.size(), local, 16);
        const auto handler = RE::TESDataHandler::GetSingleton();
        const auto formID = handler ? handler->LookupFormID(local, a_spec.substr(bar + 1)) : 0;
        return formID ? RE::TESForm::LookupByID<RE::TESNPC>(formID) : nullptr;
    }

    // The placed actor of each base (the people are unique NPCs): SkyrimNet knows actors.
    std::map<RE::TESNPC*, RE::FormID> FindActors(const std::set<RE::TESNPC*>& a_bases)
    {
        std::map<RE::TESNPC*, RE::FormID> found;
        if (a_bases.empty()) {
            return found;
        }
        const auto [forms, lock] = RE::TESForm::GetAllForms();
        RE::BSReadLockGuard guard{ lock };
        if (!forms) {
            return found;
        }
        for (const auto& [id, form] : *forms) {
            if (!form || !form->Is(RE::FormType::ActorCharacter)) {
                continue;
            }
            const auto actor = form->As<RE::Actor>();
            const auto base = actor ? actor->GetActorBase() : nullptr;
            if (base && a_bases.contains(base) && !found.contains(base) && !actor->IsDeleted()) {
                found[base] = actor->GetFormID();
            }
        }
        return found;
    }

    bool Resolve(const json& a_list, std::vector<Person>& a_out, std::string& a_bad)
    {
        std::vector<std::pair<std::string, std::string>> specs;
        for (const auto& entry : a_list) {
            specs.emplace_back(entry.value("spec", std::string()), entry.value("name", std::string()));
        }
        std::set<RE::TESNPC*>    bases;
        std::vector<RE::TESNPC*> baseOf(specs.size(), nullptr);
        for (std::size_t i = 0; i < specs.size(); ++i) {
            if (!IsPlayerWord(specs[i].first)) {
                baseOf[i] = LookUpBase(specs[i].first);
                if (!baseOf[i]) {
                    a_bad = specs[i].second.empty() ? specs[i].first : specs[i].second;
                    return false;
                }
                bases.insert(baseOf[i]);
            }
        }
        const auto actors = FindActors(bases);
        const auto player = RE::PlayerCharacter::GetSingleton();
        for (std::size_t i = 0; i < specs.size(); ++i) {
            Person p;
            if (!baseOf[i]) {
                p.ref = 0x14;
                p.player = true;
                p.name = player ? player->GetDisplayFullName() : "Player";
            } else {
                const auto it = actors.find(baseOf[i]);
                p.ref = it != actors.end() ? it->second : baseOf[i]->GetFormID();
                p.name = specs[i].second.empty() ? baseOf[i]->GetFullName() : specs[i].second;
            }
            a_out.push_back(std::move(p));
        }
        return true;
    }

    // ---- SN Sexual Memories: what its relationship maps say about these people ----

    json Relations(const std::vector<Person>& a_people)
    {
        json out = json::array();
        if (!PublicGetSaveUniqueID) {
            return out;
        }
        std::map<RE::FormID, std::string> names;
        for (const auto& p : a_people) {
            names[p.ref] = p.name;
        }
        std::string save = PublicGetSaveUniqueID();
        if (save.empty()) {
            save = "unknown_save";
        }
        for (auto& c : save) {
            if (std::string_view("\\/:*?\"<>|").find(c) != std::string_view::npos || static_cast<unsigned char>(c) < 0x20) {
                c = '_';
            }
        }
        const auto folder = std::filesystem::current_path() / "Data" / "SKSE" / "Plugins" / "SN_SexualHistory" / "relmaps" /
                            std::filesystem::path(std::u8string(save.begin(), save.end()));
        std::error_code ec;
        if (!std::filesystem::is_directory(folder, ec)) {
            return out;
        }
        std::set<std::pair<RE::FormID, RE::FormID>> seen;
        for (const auto& file : std::filesystem::directory_iterator(folder, ec)) {
            if (out.size() >= kMaxRelations || file.path().extension() != ".json") {
                continue;
            }
            json map;
            try {
                std::ifstream in(file.path(), std::ios::binary);
                map = json::parse(in);
            } catch (...) {
                continue;
            }
            if (!map.is_object() || !map.contains("people") || !map["people"].is_array()) {
                continue;
            }
            std::map<std::string, RE::FormID> idOf;
            std::map<std::string, json>       entryOf;
            for (const auto& person : map["people"]) {
                if (person.is_object() && person.contains("key") && person.contains("id") && person["id"].is_number_unsigned()) {
                    idOf[person["key"].get<std::string>()] = person["id"].get<RE::FormID>();
                    entryOf[person["key"].get<std::string>()] = person;
                }
            }
            const auto pairOf = [](RE::FormID a, RE::FormID b) { return a < b ? std::make_pair(a, b) : std::make_pair(b, a); };
            // The centre and each person: the card's role and summary.
            if (idOf.contains("c") && names.contains(idOf["c"])) {
                const auto centre = idOf["c"];
                for (const auto& [key, person] : entryOf) {
                    const auto id = idOf[key];
                    if (key == "c" || !names.contains(id) || seen.contains(pairOf(centre, id)) || out.size() >= kMaxRelations) {
                        continue;
                    }
                    const auto role = person.value("role", std::string());
                    const auto summary = person.value("summary", std::string());
                    if (role.empty() && summary.empty()) {
                        continue;
                    }
                    seen.insert(pairOf(centre, id));
                    out.push_back(std::format("{} / {}: {}{}{}", names[centre], names[id], role, role.empty() || summary.empty() ? "" : ". ", summary));
                }
            }
            // Ties between the others.
            if (map.contains("links") && map["links"].is_array()) {
                for (const auto& link : map["links"]) {
                    if (!link.is_object() || out.size() >= kMaxRelations) {
                        continue;
                    }
                    const auto a = link.value("a", std::string()), b = link.value("b", std::string());
                    const auto label = link.value("label", std::string());
                    if (!idOf.contains(a) || !idOf.contains(b) || label.empty()) {
                        continue;
                    }
                    const auto ia = idOf[a], ib = idOf[b];
                    if (!names.contains(ia) || !names.contains(ib) || ia == ib || seen.contains(pairOf(ia, ib))) {
                        continue;
                    }
                    seen.insert(pairOf(ia, ib));
                    out.push_back(std::format("{} / {}: {}", names[ia], names[ib], label));
                }
            }
        }
        return out;
    }

    // ---- requests ----

    json PeopleJson(const Job& a_job)
    {
        json people = json::array();
        for (std::size_t i = 0; i < a_job.people.size(); ++i) {
            const auto& p = a_job.people[i];
            people.push_back({ { "index", i }, { "form_id", p.ref }, { "name", p.name }, { "is_player", p.player } });
        }
        return people;
    }

    // The JSON object in an answer (the model may wrap it in ```json fences or add words).
    json ParseAnswer(const char* a_response)
    {
        const std::string text = a_response ? a_response : "";
        const auto first = text.find('{'), last = text.rfind('}');
        if (first == std::string::npos || last == std::string::npos || last < first) {
            return {};
        }
        try {
            auto parsed = json::parse(text.substr(first, last - first + 1));
            return parsed.is_object() ? parsed : json{};
        } catch (...) {
            return {};
        }
    }

    std::string Str(const json& a_object, const char* a_key)
    {
        return a_object.contains(a_key) && a_object[a_key].is_string() ? a_object[a_key].get<std::string>() : std::string();
    }

    void Ask(std::shared_ptr<Job> a_job, const char* a_prompt, json a_context, void (*a_onAnswer)(std::shared_ptr<Job>, const json&));
    void WriteNextColumn(std::shared_ptr<Job> a_job);

    std::string Trim(std::string a_text)
    {
        const auto first = a_text.find_first_not_of(" \t\r\n\"'[]()");
        const auto last = a_text.find_last_not_of(" \t\r\n\"'[]()");
        return first == std::string::npos ? std::string() : a_text.substr(first, last - first + 1);
    }

    // The person a name in an answer means (the AI answers with names: numbers got mixed up).
    // Exact first, then one name inside the other ("Alvor" / "Alvor the smith"). -1: nobody.
    int FindPerson(const Job& a_job, const json& a_value)
    {
        const int count = static_cast<int>(a_job.people.size());
        if (a_value.is_number_integer()) {
            const int index = a_value.get<int>();
            return index >= 0 && index < count ? index : -1;
        }
        if (!a_value.is_string()) {
            return -1;
        }
        const auto name = Trim(a_value.get<std::string>());
        if (name.empty()) {
            return -1;
        }
        for (int i = 0; i < count; ++i) {
            if (a_job.people[i].name == name) {
                return i;
            }
        }
        for (int i = 0; i < count; ++i) {
            const auto& other = a_job.people[i].name;
            if (!other.empty() && (name.find(other) != std::string::npos || other.find(name) != std::string::npos)) {
                return i;
            }
        }
        return -1;
    }

    void OnColumn(std::shared_ptr<Job> a_job, const json& a_answer)
    {
        auto&       plan = a_job->outline[a_job->next];
        auto&       cast = plan["cast"];  // indexes into people; a speaker missing from it joins it
        const auto  narrator = Str(a_answer, "narrator");
        json        lines = json::array();
        json        shown = json::array();
        if (a_answer.contains("lines") && a_answer["lines"].is_array()) {
            for (const auto& line : a_answer["lines"]) {
                if (!line.is_object() || lines.size() >= kMaxLines) {
                    continue;
                }
                const auto text = Str(line, "text");
                if (text.empty()) {
                    continue;
                }
                int who = 0;
                if (line.contains("who")) {
                    const auto& said = line["who"];
                    if (said.is_number_integer()) {
                        who = said.get<int>();  // an old-style answer: the place in the cast
                    } else if (const int person = FindPerson(*a_job, said); person >= 0) {
                        who = -1;
                        for (std::size_t i = 0; i < cast.size(); ++i) {
                            if (cast[i].get<int>() == person) {
                                who = static_cast<int>(i);
                            }
                        }
                        if (who < 0 && static_cast<int>(cast.size()) < kMaxCast) {
                            logger::info("Generate: column {}: {} speaks, so joins it", a_job->next + 1, a_job->people[person].name);
                            cast.push_back(person);
                            who = static_cast<int>(cast.size()) - 1;
                        }
                    }
                }
                if (who < 0 || who >= static_cast<int>(cast.size())) {
                    who = 0;
                }
                lines.push_back({ { "who", who }, { "text", text } });
                shown.push_back({ { "name", a_job->people[cast[who].get<int>()].name }, { "text", text } });
            }
        }
        a_job->written.push_back({ { "number", a_job->next + 1 }, { "narrator", narrator }, { "lines", shown } });
        a_job->result.push_back({ { "cast", cast }, { "narrator", narrator }, { "lines", lines }, { "ostim", plan["ostim"] }, { "tags", plan["tags"] } });
        a_job->next += 1;
        WriteNextColumn(a_job);
    }

    void WriteNextColumn(std::shared_ptr<Job> a_job)
    {
        const int total = static_cast<int>(a_job->outline.size());
        if (a_job->next >= total) {
            logger::info("Generate: \"{}\" done, {} columns", a_job->title, total);
            g_busy = false;
            Send({ { "type", "done" }, { "title", a_job->title }, { "plot", a_job->plot }, { "columns", a_job->result } });
            return;
        }
        Progress(a_job->next + 2, total + 1, "column");
        const auto& plan = a_job->outline[a_job->next];
        json        cast = json::array();
        for (std::size_t local = 0; local < plan["cast"].size(); ++local) {
            const int   index = plan["cast"][local].get<int>();
            const auto& p = a_job->people[index];
            cast.push_back({ { "local", local }, { "index", index }, { "form_id", p.ref }, { "name", p.name }, { "is_player", p.player } });
        }
        json outline = json::array();
        for (std::size_t i = 0; i < a_job->outline.size(); ++i) {
            std::string names;
            for (const auto& index : a_job->outline[i]["cast"]) {
                names += (names.empty() ? "" : ", ") + a_job->people[index.get<int>()].name;
            }
            outline.push_back({ { "number", i + 1 }, { "cast_names", names }, { "summary", a_job->outline[i]["summary"] }, { "ostim", a_job->outline[i]["ostim"] } });
        }
        json context = {
            { "writer", { { "form_id", a_job->writer.ref }, { "name", a_job->writer.name } } },
            { "people", PeopleJson(*a_job) },
            { "theme", a_job->theme },
            { "title", a_job->title },
            { "plot", a_job->plot },
            { "outline", outline },
            { "number", a_job->next + 1 },
            { "cast", cast },
            { "summary", plan["summary"] },
            { "ostim", plan["ostim"] },
            { "tags", plan["tags"] },
            { "written", a_job->written },
            { "relations", a_job->relations },
            { "language", a_job->language },
        };
        a_job->retried = false;
        Ask(a_job, kColumnPrompt, std::move(context), OnColumn);
    }

    void OnPlan(std::shared_ptr<Job> a_job, const json& a_answer)
    {
        a_job->title = Str(a_answer, "title");
        a_job->plot = Str(a_answer, "plot");
        std::set<std::string> known, solo;
        for (const auto& t : a_job->tags) {
            known.insert(t.value("tag", std::string()));
        }
        for (const auto& t : a_job->soloTags) {
            if (t.is_string()) {
                solo.insert(t.get<std::string>());
                known.insert(t.get<std::string>());
            }
        }
        if (a_answer.contains("columns") && a_answer["columns"].is_array()) {
            for (const auto& column : a_answer["columns"]) {
                if (!column.is_object() || static_cast<int>(a_job->outline.size()) >= a_job->columns) {
                    continue;
                }
                json             cast = json::array();
                std::set<int>    used;
                if (column.contains("cast") && column["cast"].is_array()) {
                    for (const auto& who : column["cast"]) {
                        const int index = FindPerson(*a_job, who);
                        if (index >= 0 && !used.contains(index) && static_cast<int>(cast.size()) < kMaxCast) {
                            used.insert(index);
                            cast.push_back(index);
                        } else if (index < 0) {
                            logger::warn("Generate: the plan names someone who is not taking part: {}", Dump(who));
                        }
                    }
                }
                if (cast.empty()) {
                    cast.push_back(0);
                }
                const bool ostim = column.contains("ostim") && column["ostim"].is_boolean() && column["ostim"].get<bool>();
                json       tags = json::array();
                if (ostim && column.contains("tags") && column["tags"].is_array()) {
                    for (const auto& tag : column["tags"]) {
                        if (!tag.is_string()) {
                            continue;
                        }
                        const auto t = tag.get<std::string>();
                        // a scene with one person takes only the solo tags; the others never do
                        if (cast.size() == 1 ? solo.contains(t) : (known.contains(t) && !solo.contains(t))) {
                            tags.push_back(t);
                        }
                    }
                }
                a_job->outline.push_back({ { "cast", cast }, { "summary", Str(column, "summary") }, { "ostim", ostim }, { "tags", tags } });
            }
        }
        if (a_job->outline.empty()) {
            Fail("badanswer", "the plan has no columns");
            return;
        }
        Send({ { "type", "plan" }, { "title", a_job->title }, { "plot", a_job->plot }, { "total", a_job->outline.size() + 1 } });
        a_job->next = 0;
        WriteNextColumn(a_job);
    }

    // One request; an answer that is not the JSON asked for is asked again once.
    void Ask(std::shared_ptr<Job> a_job, const char* a_prompt, json a_context, void (*a_onAnswer)(std::shared_ptr<Job>, const json&))
    {
        const auto context = Dump(a_context);
        const bool queued = PublicSendCustomPromptToLLM(a_prompt, kVariant, context.c_str(),
            [a_job, a_prompt, a_context, a_onAnswer](const char* a_response, int a_success) {
                if (a_success != 1) {
                    Fail("llm", a_response ? a_response : "");
                    return;
                }
                // In the log, to see what the AI made of the request.
                logger::info("Generate: {} answered: {}", a_prompt, std::string(a_response ? a_response : "").substr(0, 4000));
                const auto answer = ParseAnswer(a_response);
                if (answer.is_null()) {
                    if (!a_job->retried) {
                        logger::warn("Generate: {} answered without JSON; asking again", a_prompt);
                        a_job->retried = true;
                        Ask(a_job, a_prompt, a_context, a_onAnswer);
                        return;
                    }
                    Fail("badanswer", std::string(a_response ? a_response : "").substr(0, 300));
                    return;
                }
                a_job->retried = false;
                a_onAnswer(a_job, answer);
            });
        if (!queued) {
            Fail("llm", "SkyrimNet did not take the request");
        }
    }
}

namespace Generator
{
    void SetUp()
    {
        g_api = FindFunctions() && PublicSendCustomPromptToLLM != nullptr;
        logger::info("SkyrimNet C++ API: {}", g_api ? "found" : "not found (no scenario generation)");
    }

    bool Start(const std::string& a_request)
    {
        if (!g_api) {
            Fail("noapi");
            return false;
        }
        if (g_busy.exchange(true)) {
            Send({ { "type", "error" }, { "code", "busy" } });
            return false;
        }
        json request;
        try {
            request = json::parse(a_request);
        } catch (...) {
            Fail("badrequest");
            return false;
        }
        auto job = std::make_shared<Job>();
        std::string bad;
        std::vector<Person> writer;
        if (!request.contains("writer") || !Resolve(json::array({ request["writer"] }), writer, bad) ||
            !request.contains("people") || !request["people"].is_array() || !Resolve(request["people"], job->people, bad)) {
            Fail("nobody", bad);
            return false;
        }
        if (job->people.empty() || job->people.size() > kMaxPeople) {
            Fail("badrequest", "people");
            return false;
        }
        job->writer = writer.front();
        job->columns = std::clamp(request.value("columns", 1), 1, kMaxColumns);
        job->theme = request.value("theme", std::string());
        job->language = request.value("language", std::string("English"));
        if (request.contains("tags") && request["tags"].is_array()) {
            job->tags = request["tags"];
        }
        if (request.contains("solo_tags") && request["solo_tags"].is_array()) {
            job->soloTags = request["solo_tags"];
        }
        job->relations = Relations(job->people);

        json uuids = json::array();
        if (PublicFormIDToUUID) {
            for (const auto& p : job->people) {
                if (const auto uuid = PublicFormIDToUUID(p.ref)) {
                    uuids.push_back(uuid);
                }
            }
        }
        logger::info("Generate: writer {} ({:08X}), {} people, {} columns, {} relation lines", job->writer.name, job->writer.ref,
            job->people.size(), job->columns, job->relations.size());
        Progress(1, job->columns + 1, "plan");
        json context = {
            { "writer", { { "form_id", job->writer.ref }, { "name", job->writer.name }, { "is_player", job->writer.player } } },
            { "people", PeopleJson(*job) },
            { "uuids", uuids },
            { "columns", job->columns },
            { "theme", job->theme },
            { "relations", job->relations },
            { "tags", job->tags },
            { "solo_tags", job->soloTags },
            { "language", job->language },
        };
        Ask(job, kPlanPrompt, std::move(context), OnPlan);
        return true;
    }
}

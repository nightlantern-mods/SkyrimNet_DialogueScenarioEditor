#include "PrismaUI_API.h"  // first: it sets NOMINMAX and WIN32_LEAN_AND_MEAN before <windows.h>

#include "generator.h"

#include <algorithm>
#include <atomic>
#include <format>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include <nlohmann/json.hpp>

// SkyrimNet Dialogue Scenario Editor: what the Papyrus mod cannot do itself.
//
// 1. The Prisma UI host for the settings page. Magelight UI has a Papyrus API, so with Magelight
//    UI the page is driven from Papyrus alone; Prisma UI can only be driven from an SKSE plugin.
//    This creates the (hidden) Prisma UI view, shows and hides it, runs JavaScript in it, and
//    turns the page's calls (window.dse_*(text)) into SKSE mod events "DSE_Prisma_dse_*"
//    (strArg = the text) for the Papyrus script SkyrimNet_DialogueScenarioEditorUI.
// 2. Scenario generation (generator.h): SkyrimNet's LLM through its C++ API, whose answers are
//    not cut short as the Papyrus one's are.
//
// Papyrus: SkyrimNet_DialogueScenarioEditorNative (global natives).

namespace
{
    constexpr const char* kScript = "SkyrimNet_DialogueScenarioEditorNative";
    constexpr const char* kViewPath = "SkyrimNet_DialogueScenarioEditor/index.html";  // under Data/PrismaUI/views
    constexpr const char* kEventPrefix = "DSE_Prisma_";
    constexpr const char* kListeners[] = { "dse_ready", "dse_close", "dse_save", "dse_delete", "dse_npcs", "dse_generate", "dse_places", "dse_here" };

    PRISMA_UI_API::IVPrismaUI1* g_prisma = nullptr;
    PrismaView                  g_view = 0;
    std::atomic<bool>           g_open = false;
    bool                        g_magelight = false;  // Magelight.dll is loaded (the Papyrus side then prefers it)

    // Game thread.
    void SendModEvent(const std::string& a_name, const std::string& a_text)
    {
        SKSE::ModCallbackEvent event{ RE::BSFixedString(a_name.c_str()), RE::BSFixedString(a_text.c_str()), 0.0f, nullptr };
        SKSE::GetModCallbackEventSource()->SendEvent(&event);
    }

    // The page's calls arrive on Prisma UI's thread: the event is sent from the game thread.
    template <std::size_t I>
    void OnPageCall(const char* a_argument)
    {
        std::string name = std::string(kEventPrefix) + kListeners[I];
        std::string text = a_argument ? a_argument : "";
        SKSE::GetTaskInterface()->AddTask([name = std::move(name), text = std::move(text)]() { SendModEvent(name, text); });
    }

    template <std::size_t... I>
    void RegisterListeners(std::index_sequence<I...>)
    {
        (g_prisma->RegisterJSListener(g_view, kListeners[I], OnPageCall<I>), ...);
    }

    void Invoke(const std::string& a_script)
    {
        if (g_prisma && g_view) {
            g_prisma->Invoke(g_view, a_script.c_str());
        }
    }

    void ClosePage()
    {
        if (!g_prisma || !g_view) {
            return;
        }
        g_open = false;
        if (g_prisma->HasFocus(g_view)) {
            g_prisma->Unfocus(g_view);
        }
        g_prisma->Hide(g_view);
    }

    // ---- Papyrus ----

    // Bit 1: Magelight UI is loaded. Bit 2: the Prisma UI view exists.
    std::int32_t HostNative(RE::StaticFunctionTag*)
    {
        return (g_magelight ? 1 : 0) | (g_prisma && g_view ? 2 : 0);
    }

    bool OpenNative(RE::StaticFunctionTag*)
    {
        if (!g_prisma || !g_view) {
            return false;
        }
        if (g_prisma->HasAnyActiveFocus() && !g_prisma->HasFocus(g_view)) {
            return false;  // another Prisma UI view has the input
        }
        SKSE::GetTaskInterface()->AddUITask([]() {
            g_prisma->Show(g_view);
            if (g_prisma->Focus(g_view, true)) {
                g_open = true;
            } else {
                logger::warn("Prisma UI did not give the page the input");
                g_prisma->Hide(g_view);
            }
        });
        return true;
    }

    void CloseNative(RE::StaticFunctionTag*)
    {
        SKSE::GetTaskInterface()->AddUITask(ClosePage);
    }

    bool IsOpenNative(RE::StaticFunctionTag*)
    {
        return g_open;
    }

    void EvalNative(RE::StaticFunctionTag*, RE::BSFixedString a_script)
    {
        std::string script = a_script.c_str();
        SKSE::GetTaskInterface()->AddUITask([script = std::move(script)]() { Invoke(script); });
    }

    std::int32_t VersionNative(RE::StaticFunctionTag*)
    {
        return 3;
    }

    // The Papyrus scripts' log: written here so players can send it without turning on Papyrus
    // logging in their INI. a_level: 0 info, 1 warning, 2 error.
    void LogNative(RE::StaticFunctionTag*, RE::BSFixedString a_text, std::int32_t a_level)
    {
        const char* text = a_text.c_str() ? a_text.c_str() : "";
        if (a_level >= 2) {
            logger::error("[papyrus] {}", text);
        } else if (a_level == 1) {
            logger::warn("[papyrus] {}", text);
        } else {
            logger::info("[papyrus] {}", text);
        }
    }

    // What the log needs to tell a setup apart: the game, the mods this one works with, and the
    // plugins they come in.
    void LogEnvironment()
    {
        const auto ver = REL::Module::get().version();
        logger::info("Game {}.{}.{}.{}", ver[0], ver[1], ver[2], ver[3]);
        for (const auto* dll : { "SkyrimNet.dll", "OStim.dll", "PapyrusUtil.dll", "po3_PapyrusExtender.dll", "Magelight.dll",
                 "PrismaUI.dll", "MCMHelper.dll" }) {
            logger::info("  {}: {}", dll, GetModuleHandleA(dll) ? "loaded" : "not loaded");
        }
        if (const auto handler = RE::TESDataHandler::GetSingleton()) {
            for (const auto* plugin : { "SkyrimNet.esp", "OStim.esp", "SkyrimNet_DialogueScenarioEditor.esp", "SN_SexualHistory.esp" }) {
                const auto file = handler->LookupModByName(plugin);
                logger::info("  {}: {}", plugin, file ? "active" : "not active");
            }
        }
    }

    // Every unique, named adult person of the load order, for the page's NPC picker, as a JSON
    // array of [formID, plugin, name] (what the Papyrus scan sends, in well under a second).
    RE::BSFixedString NpcListNative(RE::StaticFunctionTag*)
    {
        auto       list = nlohmann::json::array();
        const auto npcKeyword = RE::TESForm::LookupByEditorID<RE::BGSKeyword>("ActorTypeNPC");
        const auto [forms, lock] = RE::TESForm::GetAllForms();
        {
            RE::BSReadLockGuard guard{ lock };
            if (forms) {
                for (const auto& [id, form] : *forms) {
                    if (!form || form->GetFormType() != RE::FormType::NPC) {
                        continue;
                    }
                    const auto npc = form->As<RE::TESNPC>();
                    const auto race = npc ? npc->GetRace() : nullptr;
                    const char* name = npc ? npc->GetFullName() : nullptr;
                    if (!npc || !npc->IsUnique() || !race || !name || !*name || race->data.flags.all(RE::RACE_DATA::Flag::kChild) ||
                        (npcKeyword && !race->HasKeyword(npcKeyword))) {
                        continue;
                    }
                    const auto file = npc->GetFile(0);
                    list.push_back({ npc->GetFormID(), file ? std::string(file->GetFilename()) : std::string(), std::string(name) });
                }
            }
        }
        logger::info("NPC list: {} people", list.size());
        return list.dump(-1, ' ', false, nlohmann::json::error_handler_t::replace);
    }

    // ---- Places (the column end "move and wait") ----
    // Named interior places, each with the inside door of a load door that leads there: the
    // anchor an NPC is sent to. Load doors are persistent, so this works for cells that are not
    // loaded. Built once, on first use.
    struct Place
    {
        RE::FormID  cell = 0;
        RE::FormID  anchor = 0;
        std::string spec;  // "0xLOCAL|plugin", as the page stores it
        std::string name;
        std::string editorID;
    };
    std::vector<Place>                       g_places;
    std::unordered_map<std::string, size_t>  g_placeBySpec;
    std::once_flag                           g_placesBuilt;

    std::string SpecOf(const RE::TESForm* a_form)
    {
        const auto file = a_form->GetFile(0);
        if (!file) {
            return {};
        }
        const auto local = file->IsLight() ? (a_form->GetFormID() & 0xFFF) : (a_form->GetFormID() & 0xFFFFFF);
        return std::format("0x{:X}|{}", local, file->GetFilename());
    }

    void BuildPlaces()
    {
        std::unordered_map<RE::FormID, RE::FormID> anchorOf;  // cell -> inside door
        {
            const auto [forms, lock] = RE::TESForm::GetAllForms();
            RE::BSReadLockGuard guard{ lock };
            if (forms) {
                for (const auto& [id, form] : *forms) {
                    const auto ref = form ? form->AsReference() : nullptr;
                    const auto base = ref ? ref->GetBaseObject() : nullptr;
                    if (!base || base->GetFormType() != RE::FormType::Door) {
                        continue;
                    }
                    const auto teleport = ref->extraList.GetByType<RE::ExtraTeleport>();
                    if (!teleport || !teleport->teleportData) {
                        continue;
                    }
                    const auto inside = teleport->teleportData->linkedDoor.get();
                    const auto cell = inside ? inside->GetParentCell() : nullptr;
                    if (!cell || !cell->IsInteriorCell() || anchorOf.contains(cell->GetFormID())) {
                        continue;
                    }
                    anchorOf[cell->GetFormID()] = inside->GetFormID();
                }
            }
        }
        for (const auto& [cellID, anchor] : anchorOf) {
            const auto cell = RE::TESForm::LookupByID<RE::TESObjectCELL>(cellID);
            const char* name = cell ? cell->GetFullName() : nullptr;
            if (!cell || !name || !*name) {
                continue;
            }
            Place p{ cellID, anchor, SpecOf(cell), name, cell->GetFormEditorID() };
            if (p.spec.empty()) {
                continue;
            }
            g_places.push_back(std::move(p));
        }
        std::ranges::sort(g_places, [](const Place& a, const Place& b) { return a.name < b.name; });
        for (size_t i = 0; i < g_places.size(); ++i) {
            g_placeBySpec[g_places[i].spec] = i;
        }
        logger::info("Places: {} named interiors with a load door", g_places.size());
    }

    // [[spec, name, editorID], ...] for the page's place picker.
    RE::BSFixedString PlaceListNative(RE::StaticFunctionTag*)
    {
        std::call_once(g_placesBuilt, BuildPlaces);
        auto list = nlohmann::json::array();
        for (const auto& p : g_places) {
            list.push_back({ p.spec, p.name, p.editorID });
        }
        return list.dump(-1, ' ', false, nlohmann::json::error_handler_t::replace);
    }

    // The player's cell for the page's "this cell" button (a scenario's cell condition), as a JSON
    // array [spec, name, interior] ("" when there is none). Exterior cells rarely have a name of
    // their own: the location's name and the grid position stand in.
    RE::BSFixedString HereCellNative(RE::StaticFunctionTag*)
    {
        const auto player = RE::PlayerCharacter::GetSingleton();
        const auto cell = player ? player->GetParentCell() : nullptr;
        if (!cell) {
            return "";
        }
        const auto spec = SpecOf(cell);
        if (spec.empty()) {
            return "";  // a cell made at runtime has no file
        }
        std::string name = cell->GetFullName() ? cell->GetFullName() : "";
        const bool  interior = cell->IsInteriorCell();
        if (!interior) {
            std::string where;
            if (const auto location = cell->GetLocation(); location && location->GetFullName()) {
                where = location->GetFullName();
            }
            if (where.empty() && name.empty()) {
                where = cell->GetFormEditorID() ? cell->GetFormEditorID() : "";
            }
            const auto grid = cell->GetCoordinates();
            name = std::format("{}{}{} ({}, {})", name, (!name.empty() && !where.empty()) ? " / " : "", where,
                grid ? grid->cellX : 0, grid ? grid->cellY : 0);
        } else if (name.empty()) {
            name = cell->GetFormEditorID() ? cell->GetFormEditorID() : spec;
        }
        logger::info("Here: {} {} ({})", spec, name, interior ? "interior" : "exterior");
        return nlohmann::json::array({ spec, name, interior }).dump(-1, ' ', false, nlohmann::json::error_handler_t::replace);
    }

    // The inside door of a place chosen on the page (its spec), or None.
    RE::TESObjectREFR* PlaceAnchorNative(RE::StaticFunctionTag*, RE::BSFixedString a_spec)
    {
        std::call_once(g_placesBuilt, BuildPlaces);
        const auto it = g_placeBySpec.find(a_spec.c_str());
        if (it == g_placeBySpec.end()) {
            logger::warn("PlaceAnchor: unknown place {}", a_spec.c_str());
            return nullptr;
        }
        return RE::TESForm::LookupByID<RE::TESObjectREFR>(g_places[it->second].anchor);
    }

    // The settings page's Generate. False: it did not start (a DSE_Gen error says why).
    bool GenerateNative(RE::StaticFunctionTag*, RE::BSFixedString a_request)
    {
        return Generator::Start(a_request.c_str());
    }

    bool RegisterPapyrus(RE::BSScript::IVirtualMachine* a_vm)
    {
        a_vm->RegisterFunction("Generate", kScript, GenerateNative);
        a_vm->RegisterFunction("Version", kScript, VersionNative);
        a_vm->RegisterFunction("Log", kScript, LogNative);
        a_vm->RegisterFunction("HereCell", kScript, HereCellNative);
        a_vm->RegisterFunction("NpcList", kScript, NpcListNative);
        a_vm->RegisterFunction("PlaceList", kScript, PlaceListNative);
        a_vm->RegisterFunction("PlaceAnchor", kScript, PlaceAnchorNative);
        a_vm->RegisterFunction("Host", kScript, HostNative);
        a_vm->RegisterFunction("Open", kScript, OpenNative);
        a_vm->RegisterFunction("Close", kScript, CloseNative);
        a_vm->RegisterFunction("IsOpen", kScript, IsOpenNative);
        a_vm->RegisterFunction("Eval", kScript, EvalNative);
        return true;
    }

    // ---- Game events ----

    // Esc goes to the page (it closes the NPC picker first, then the page): the page does not
    // always get the key itself while it has the input.
    class EscapeWatcher : public RE::BSTEventSink<RE::InputEvent*>
    {
    public:
        static EscapeWatcher* GetSingleton()
        {
            static EscapeWatcher singleton;
            return &singleton;
        }

        RE::BSEventNotifyControl ProcessEvent(RE::InputEvent* const* a_events, RE::BSTEventSource<RE::InputEvent*>*) override
        {
            if (!g_open || !a_events) {
                return RE::BSEventNotifyControl::kContinue;
            }
            for (auto event = *a_events; event; event = event->next) {
                const auto button = event->AsButtonEvent();
                // On release: closing on the press gives the game its controls back while Esc is
                // still down, and the game opens its own Esc menu as the page closes.
                if (button && button->GetDevice() == RE::INPUT_DEVICE::kKeyboard &&
                    button->GetIDCode() == RE::BSKeyboardDevice::Key::kEscape && button->IsUp()) {
                    SKSE::GetTaskInterface()->AddUITask([]() {
                        if (g_open && g_prisma->HasFocus(g_view)) {
                            Invoke("dseEscape()");
                        } else {
                            ClosePage();
                        }
                    });
                }
            }
            return RE::BSEventNotifyControl::kContinue;
        }
    };

    // A load closes the page (the Papyrus side starts over).
    class LoadWatcher : public RE::BSTEventSink<RE::TESLoadGameEvent>
    {
    public:
        static LoadWatcher* GetSingleton()
        {
            static LoadWatcher singleton;
            return &singleton;
        }

        RE::BSEventNotifyControl ProcessEvent(const RE::TESLoadGameEvent*, RE::BSTEventSource<RE::TESLoadGameEvent>*) override
        {
            SKSE::GetTaskInterface()->AddUITask(ClosePage);
            return RE::BSEventNotifyControl::kContinue;
        }
    };

    void SetUp()
    {
        g_magelight = GetModuleHandleW(L"Magelight.dll") != nullptr;
        g_prisma = static_cast<PRISMA_UI_API::IVPrismaUI1*>(PRISMA_UI_API::RequestPluginAPI(PRISMA_UI_API::InterfaceVersion::V1));
        if (!g_prisma) {
            logger::info("Prisma UI is not installed (Magelight UI: {})", g_magelight);
            return;
        }
        if (g_magelight) {
            // Both are installed: the page uses Magelight UI (from Papyrus), so no second view.
            logger::info("Magelight UI and Prisma UI are both installed: the page uses Magelight UI");
            g_prisma = nullptr;
            return;
        }
        g_view = g_prisma->CreateView(kViewPath, [](PrismaView a_view) -> void {
            logger::info("Prisma UI view DOM is ready {}", a_view);
        });
        if (!g_view) {
            logger::error("Prisma UI did not create the view {}", kViewPath);
            return;
        }
        g_prisma->Hide(g_view);
        RegisterListeners(std::make_index_sequence<std::size(kListeners)>{});

        if (const auto events = RE::ScriptEventSourceHolder::GetSingleton()) {
            events->AddEventSink<RE::TESLoadGameEvent>(LoadWatcher::GetSingleton());
        }
        if (const auto input = RE::BSInputDeviceManager::GetSingleton()) {
            input->AddEventSink(EscapeWatcher::GetSingleton());
        }
        logger::info("The page uses Prisma UI");
    }

    void OnSKSEMessage(SKSE::MessagingInterface::Message* a_message)
    {
        if (a_message->type == SKSE::MessagingInterface::kDataLoaded) {
            LogEnvironment();
            Generator::SetUp();
            SetUp();
        }
    }
}

extern "C" DLLEXPORT bool SKSEPlugin_Load(const SKSE::LoadInterface* a_skse)
{
    REL::Module::reset();

    const auto messaging = reinterpret_cast<SKSE::MessagingInterface*>(a_skse->QueryInterface(SKSE::LoadInterface::kMessaging));
    if (!messaging) {
        logger::critical("Failed to load the messaging interface; the plugin will not load.");
        return false;
    }

    SKSE::Init(a_skse);
    spdlog::default_logger()->flush_on(spdlog::level::trace);
    logger::info("SkyrimNet_DialogueScenarioEditor loaded");

    SKSE::GetPapyrusInterface()->Register(RegisterPapyrus);
    messaging->RegisterListener("SKSE", OnSKSEMessage);
    return true;
}

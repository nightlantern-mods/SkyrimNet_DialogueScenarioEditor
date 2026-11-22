#include "actions.h"

#include <nlohmann/json.hpp>

#include <filesystem>
#include <fstream>
#include <mutex>
#include <unordered_map>

using json = nlohmann::json;

namespace
{
    struct Param
    {
        std::string name;
        std::string type;
        std::string desc;
        bool        optional = false;
    };

    struct Action
    {
        std::string        name;
        std::string        mod;
        std::string        desc;
        std::string        actionType;
        bool               enabled = true;
        bool               runs = false;  // has executionFunctionName or eventString: something to run
        std::vector<Param> params;
    };

    std::vector<Action>                     g_actions;
    std::unordered_map<std::string, size_t> g_byName;
    std::once_flag                          g_read;

    std::string Lower(std::string a_text)
    {
        for (auto& c : a_text) {
            c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
        }
        return a_text;
    }

    std::string Trim(const std::string& a_text)
    {
        const auto first = a_text.find_first_not_of(" \t\r\n");
        if (first == std::string::npos) {
            return {};
        }
        return a_text.substr(first, a_text.find_last_not_of(" \t\r\n") - first + 1);
    }

    std::size_t Indent(const std::string& a_line)
    {
        const auto first = a_line.find_first_not_of(' ');
        return first == std::string::npos ? a_line.size() : first;
    }

    // A scalar value: quotes taken off, a trailing comment dropped from an unquoted one.
    std::string Scalar(std::string a_value)
    {
        a_value = Trim(a_value);
        if (a_value.size() >= 2 && (a_value.front() == '"' || a_value.front() == '\'')) {
            const char quote = a_value.front();
            const auto end = a_value.rfind(quote);
            std::string inner = a_value.substr(1, end > 0 ? end - 1 : std::string::npos);
            if (quote == '"') {
                std::string out;
                for (std::size_t i = 0; i < inner.size(); ++i) {
                    if (inner[i] == '\\' && i + 1 < inner.size()) {
                        ++i;
                        out += inner[i] == 'n' ? ' ' : inner[i];
                    } else {
                        out += inner[i];
                    }
                }
                return out;
            }
            std::string out;  // single quotes: '' is one quote
            for (std::size_t i = 0; i < inner.size(); ++i) {
                out += inner[i];
                if (inner[i] == '\'' && i + 1 < inner.size() && inner[i + 1] == '\'') {
                    ++i;
                }
            }
            return out;
        }
        if (const auto hash = a_value.find(" #"); hash != std::string::npos) {
            a_value = Trim(a_value.substr(0, hash));
        }
        return a_value;
    }

    // "key: value" -> key and the raw value; false when the line is not one.
    bool KeyValue(const std::string& a_text, std::string& a_key, std::string& a_value)
    {
        const auto colon = a_text.find(':');
        if (colon == std::string::npos || colon == 0) {
            return false;
        }
        a_key = Trim(a_text.substr(0, colon));
        if (a_key.empty() || a_key.find(' ') != std::string::npos) {
            return false;
        }
        a_value = a_text.substr(colon + 1);
        return true;
    }

    // A value that goes on below its key: a block scalar (| or >) or plain lines indented deeper.
    std::string Continued(const std::vector<std::string>& a_lines, std::size_t& a_at, std::size_t a_keyIndent, std::string a_first)
    {
        a_first = Trim(a_first);
        const bool block = !a_first.empty() && (a_first[0] == '|' || a_first[0] == '>');
        std::string out = block ? std::string() : Scalar(a_first);
        while (a_at + 1 < a_lines.size()) {
            const auto& next = a_lines[a_at + 1];
            if (Trim(next).empty()) {
                ++a_at;
                continue;
            }
            if (Indent(next) <= a_keyIndent) {
                break;
            }
            const auto part = Trim(next);
            if (!block && (part.starts_with("- ") || (part.find(':') != std::string::npos && part.back() != '"'))) {
                break;  // the next key of a nested map, not a continued value
            }
            out += (out.empty() ? "" : " ") + (block ? part : Scalar(part));
            ++a_at;
        }
        return out;
    }

    std::string ModName(const std::filesystem::path& a_folder, const std::string& a_fallback)
    {
        std::ifstream in(a_folder / "manifest.json");
        if (in) {
            try {
                const auto manifest = json::parse(in, nullptr, false);
                if (manifest.is_object()) {
                    for (const auto* key : { "name", "display_name", "displayName", "title" }) {
                        if (manifest.contains(key) && manifest[key].is_string() && !manifest[key].get<std::string>().empty()) {
                            return manifest[key].get<std::string>();
                        }
                    }
                }
            } catch (...) {
            }
        }
        return a_fallback;
    }

    std::string Readable(std::string a_text)
    {
        for (const auto* player : { "{{ player.name }}", "{{player.name}}" }) {
            for (auto at = a_text.find(player); at != std::string::npos; at = a_text.find(player)) {
                a_text.replace(at, std::strlen(player), "the player");
            }
        }
        return a_text;
    }

    void ReadFile(const std::filesystem::path& a_file, const std::string& a_mod)
    {
        std::ifstream in(a_file, std::ios::binary);
        if (!in) {
            return;
        }
        std::vector<std::string> lines;
        for (std::string line; std::getline(in, line);) {
            if (!line.empty() && line.back() == '\r') {
                line.pop_back();
            }
            if (lines.empty() && line.starts_with("\xEF\xBB\xBF")) {
                line = line.substr(3);
            }
            if (Trim(line).starts_with("#")) {
                line.clear();
            }
            lines.push_back(line);
        }
        Action      action;
        action.mod = a_mod;
        bool inParams = false;
        Param* param = nullptr;
        std::size_t paramIndent = 0;
        for (std::size_t i = 0; i < lines.size(); ++i) {
            const auto& line = lines[i];
            if (Trim(line).empty()) {
                continue;
            }
            const auto indent = Indent(line);
            std::string text = line.substr(indent);
            std::string key, value;
            if (indent == 0) {
                inParams = false;
                param = nullptr;
                if (!KeyValue(text, key, value)) {
                    continue;
                }
                if (key == "name") {
                    action.name = Scalar(value);
                } else if (key == "description") {
                    action.desc = Continued(lines, i, 0, value);
                } else if (key == "actionType") {
                    action.actionType = Scalar(value);
                } else if (key == "enabled") {
                    action.enabled = Scalar(value) != "false";
                } else if (key == "parameterMapping") {
                    inParams = true;
                } else if (key == "executionFunctionName" || key == "eventString") {
                    action.runs = action.runs || !Scalar(value).empty();
                }
                continue;
            }
            if (!inParams) {
                continue;
            }
            bool newItem = false;
            if (text.starts_with("- ")) {
                action.params.push_back({});
                param = &action.params.back();
                paramIndent = indent;
                text = Trim(text.substr(2));
                newItem = true;
            }
            if (!param || (!newItem && indent <= paramIndent) || !KeyValue(text, key, value)) {
                continue;
            }
            const auto keyIndent = newItem ? indent + 2 : indent;
            if (key == "name") {
                param->name = Scalar(value);
            } else if (key == "type") {
                param->type = Scalar(value);
            } else if (key == "description") {
                param->desc = Continued(lines, i, keyIndent, value);
            } else if (key == "optional") {
                param->optional = Scalar(value) == "true";
            }
        }
        // A category (a folder of actions for the AI) has nothing to run and no parameters; some mods
        // mark it with actionType: category, others (SeverActions) only leave the execution out.
        const bool category = action.actionType == "category" || (!action.runs && action.params.empty());
        if (action.name.empty() || category || !action.enabled) {
            return;
        }
        action.desc = Readable(action.desc);
        for (auto& p : action.params) {
            p.desc = Readable(p.desc);
        }
        const auto key = Lower(action.name);
        if (const auto it = g_byName.find(key); it != g_byName.end()) {
            g_actions[it->second] = std::move(action);  // config/actions (read last) overrides a mod's own file
            return;
        }
        g_byName[key] = g_actions.size();
        g_actions.push_back(std::move(action));
    }

    void ReadFolder(const std::filesystem::path& a_folder, const std::string& a_mod)
    {
        std::error_code ec;
        if (!std::filesystem::is_directory(a_folder, ec)) {
            return;
        }
        for (const auto& entry : std::filesystem::recursive_directory_iterator(a_folder, ec)) {
            const auto ext = entry.path().extension().string();
            if (entry.is_regular_file(ec) && (ext == ".yaml" || ext == ".yml")) {
                ReadFile(entry.path(), a_mod);
            }
        }
    }

    void ReadAll()
    {
        const auto root = std::filesystem::current_path() / "Data" / "SKSE" / "Plugins" / "SkyrimNet";
        std::error_code ec;
        for (const auto& mod : std::filesystem::directory_iterator(root / "external", ec)) {
            if (mod.is_directory(ec)) {
                const auto folder = mod.path().filename().string();
                ReadFolder(mod.path() / "actions", ModName(mod.path(), folder));
            }
        }
        ReadFolder(root / "config" / "actions", "SkyrimNet config");
        logger::info("Actions: {} from action files", g_actions.size());
    }
}

namespace Actions
{
    std::vector<std::string> Names()
    {
        std::call_once(g_read, ReadAll);
        std::vector<std::string> names;
        names.reserve(g_actions.size());
        for (const auto& a : g_actions) {
            names.push_back(a.name);
        }
        return names;
    }

    std::string ListJson(const std::vector<std::string>& a_names)
    {
        std::call_once(g_read, ReadAll);
        json list = json::array();
        for (const auto& name : a_names) {
            const auto it = g_byName.find(Lower(name));  // Papyrus strings come back in any letter case
            if (it == g_byName.end()) {
                continue;
            }
            const auto& a = g_actions[it->second];
            json params = json::array();
            for (const auto& p : a.params) {
                if (p.type == "dynamic" && !p.name.empty()) {
                    params.push_back({ { "n", p.name }, { "d", p.desc }, { "o", p.optional } });
                }
            }
            list.push_back({ { "n", a.name }, { "m", a.mod }, { "d", a.desc }, { "p", params } });
        }
        std::sort(list.begin(), list.end(), [](const json& x, const json& y) {
            const auto mx = x["m"].get<std::string>(), my = y["m"].get<std::string>();
            return mx != my ? mx < my : x["n"].get<std::string>() < y["n"].get<std::string>();
        });
        logger::info("Actions: {} of {} registered in SkyrimNet", list.size(), g_actions.size());
        return list.dump(-1, ' ', false, json::error_handler_t::replace);
    }
}

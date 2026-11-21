#include "PrismaUI_API.h"  // first: it sets NOMINMAX and WIN32_LEAN_AND_MEAN before <windows.h>

#include "generator.h"

#include <atomic>
#include <string>

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
    constexpr const char* kListeners[] = { "dse_ready", "dse_close", "dse_save", "dse_delete", "dse_npcs", "dse_generate" };

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
        return 1;
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

    // The settings page's Generate. False: it did not start (a DSE_Gen error says why).
    bool GenerateNative(RE::StaticFunctionTag*, RE::BSFixedString a_request)
    {
        return Generator::Start(a_request.c_str());
    }

    bool RegisterPapyrus(RE::BSScript::IVirtualMachine* a_vm)
    {
        a_vm->RegisterFunction("Generate", kScript, GenerateNative);
        a_vm->RegisterFunction("Version", kScript, VersionNative);
        a_vm->RegisterFunction("NpcList", kScript, NpcListNative);
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

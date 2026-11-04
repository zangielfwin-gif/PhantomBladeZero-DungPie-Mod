#include <windows.h>
#include <xaudio2.h>

namespace {
constexpr unsigned kRate = 48000;
constexpr unsigned kVoiceCount = 10;
constexpr unsigned kFirstResource = 101;
constexpr unsigned kPrewarm = 4;
IXAudio2* engine = nullptr;
IXAudio2MasteringVoice* output = nullptr;
IXAudio2SourceVoice* voices[kVoiceCount] = {};
HMODULE module = nullptr;
ULONGLONG last_failure = 0;
INIT_ONCE start_once = INIT_ONCE_STATIC_INIT;
SRWLOCK requests_lock = SRWLOCK_INIT;
CONDITION_VARIABLE requests_ready = CONDITION_VARIABLE_INIT;

struct Request {
    unsigned clip, pan, volume;
    HANDLE completed;
    HRESULT* result;
};
constexpr unsigned kQueueSize = 16;
Request requests[kQueueSize]{};
unsigned next_request = 0, request_count = 0;

HRESULT initialize() noexcept {
    if (output) return S_OK;
    if (last_failure && GetTickCount64() - last_failure < 1500) return E_FAIL;
    auto hr = XAudio2Create(&engine);
    if (SUCCEEDED(hr)) hr = engine->CreateMasteringVoice(&output, 2);
    if (FAILED(hr)) {
        if (engine) engine->Release();
        engine = nullptr;
        last_failure = GetTickCount64();
    }
    return hr;
}

HRESULT play(unsigned clip, unsigned pan, unsigned volume) noexcept {
    auto hr = initialize();
    if (FAILED(hr)) return hr;
    const auto res = FindResourceW(module, MAKEINTRESOURCEW(kFirstResource + clip), MAKEINTRESOURCEW(10));
    if (!res) return HRESULT_FROM_WIN32(GetLastError());
    const auto loaded = LoadResource(module, res);
    if (!loaded) return HRESULT_FROM_WIN32(GetLastError());
    const auto* pcm = static_cast<const BYTE*>(LockResource(loaded));
    const auto size = SizeofResource(module, res);
    if (!pcm || !size || size % 2) return E_FAIL;

    for (auto& voice : voices) {
        if (voice) {
            XAUDIO2_VOICE_STATE state{};
            voice->GetState(&state, XAUDIO2_VOICE_NOSAMPLESPLAYED);
            if (state.BuffersQueued) continue;
        } else {
            constexpr WAVEFORMATEX fmt{WAVE_FORMAT_PCM, 1, kRate, kRate * 2, 2, 16, 0};
            hr = engine->CreateSourceVoice(&voice, &fmt, 0, 1.0f);
            if (FAILED(hr)) return hr;
            hr = voice->Start();
            if (FAILED(hr)) {
                voice->DestroyVoice();
                voice = nullptr;
                return hr;
            }
        }
        constexpr float left[] = {.966f, .866f, .707f, .5f, .259f};
        constexpr float right[] = {.259f, .5f, .707f, .866f, .966f};
#ifdef PBZ_AUDIO_TEST
        (void)volume;
        const float amplitude = 0; // Exercise the Windows device silently.
#else
        constexpr float gain[] = {.19f, .34f, .49f, .64f, .78f};
        const float amplitude = gain[volume];
#endif
        const float matrix[] = {left[pan] * amplitude, right[pan] * amplitude};
        hr = voice->SetOutputMatrix(output, 1, 2, matrix);
        if (FAILED(hr)) return hr;
        XAUDIO2_BUFFER buffer{};
        buffer.Flags = XAUDIO2_END_OF_STREAM;
        buffer.AudioBytes = size;
        buffer.pAudioData = pcm;
        return voice->SubmitSourceBuffer(&buffer);
    }
    return S_FALSE; // Bound overlap if all voices are busy.
}

DWORD WINAPI audio_worker(void*) noexcept {
    // The audio thread owns COM, all voices and the output device.
    const auto com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    for (;;) {
        AcquireSRWLockExclusive(&requests_lock);
        while (!request_count)
            SleepConditionVariableSRW(&requests_ready, &requests_lock, INFINITE, 0);
        const auto request = requests[next_request];
        next_request = (next_request + 1) % kQueueSize;
        --request_count;
        ReleaseSRWLockExclusive(&requests_lock);

        const auto hr = FAILED(com) ? com :
            (request.clip == kPrewarm ? initialize() : play(request.clip, request.pan, request.volume));
        if (FAILED(hr)) OutputDebugStringW(L"PBZThrowAudio: failed to queue a cue.\n");
        if (request.completed) {
            *request.result = hr;
            SetEvent(request.completed);
        }
    }
}

BOOL CALLBACK start_worker(PINIT_ONCE, void*, void**) noexcept {
    // Queued audio references this DLL's code and data across Lua reloads.
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                            reinterpret_cast<LPCWSTR>(&module), &module)) return FALSE;
    const auto thread = CreateThread(nullptr, 0, audio_worker, nullptr, 0, nullptr);
    if (!thread) return FALSE;
    CloseHandle(thread);
    return TRUE;
}

HRESULT enqueue(Request request) noexcept {
    if (!InitOnceExecuteOnce(&start_once, start_worker, nullptr, nullptr)) return E_FAIL;
    AcquireSRWLockExclusive(&requests_lock);
    const bool has_space = request_count < kQueueSize;
    if (has_space) {
        requests[(next_request + request_count) % kQueueSize] = request;
        ++request_count;
    }
    ReleaseSRWLockExclusive(&requests_lock);
    if (has_space) WakeConditionVariable(&requests_ready);
    return has_space ? S_OK : S_FALSE;
}
}

// Lua calls these zero-argument functions through package.loadlib. They do not
// read or write the Lua stack or depend on the UE4SS Lua C API/Unreal ABI.
#define CUE(name, clip, pan, vol) \
    extern "C" __declspec(dllexport) int PBZ_##name##_##pan##_##vol(void*) noexcept { \
        enqueue({clip, pan, vol, nullptr, nullptr}); \
        return 0; \
    }
#define GAINS(name, clip, pan) CUE(name,clip,pan,0) CUE(name,clip,pan,1) CUE(name,clip,pan,2) CUE(name,clip,pan,3) CUE(name,clip,pan,4)
#define PANS(name, clip) GAINS(name,clip,0) GAINS(name,clip,1) GAINS(name,clip,2) GAINS(name,clip,3) GAINS(name,clip,4)
PANS(DungRelease, 0)
PANS(DungImpact, 1)
PANS(StalkRelease, 2)
PANS(StalkImpact, 3)
extern "C" __declspec(dllexport) int PBZ_Prewarm(void*) noexcept {
    enqueue({kPrewarm, 0, 0, nullptr, nullptr});
    return 0;
}

#ifdef PBZ_AUDIO_TEST
extern "C" __declspec(dllexport) HRESULT PBZ_TestCue(unsigned clip, unsigned pan, unsigned vol) noexcept {
    if (clip >= 4 || pan >= 5 || vol >= 5) return E_INVALIDARG;
    const auto done = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!done) return E_FAIL;
    HRESULT result = E_FAIL;
    const auto queued = enqueue({clip, pan, vol, done, &result});
    if (queued == S_OK) WaitForSingleObject(done, INFINITE);
    CloseHandle(done);
    return queued == S_OK ? result : queued;
}
#endif

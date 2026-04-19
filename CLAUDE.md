# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

xiaozhi-esp32-server is the backend server for the xiaozhi-esp32 open-source smart hardware project (ESP32-based AI voice assistant). It handles real-time audio streaming via WebSocket, integrates multiple AI providers (ASR, TTS, LLM, VAD, vision), manages IoT devices, and provides an admin console. The system communicates with ESP32 devices using the xiaozhi communication protocol.

## Development Commands

### Python Server (xiaozhi-server)
```bash
cd main/xiaozhi-server
pip install -r requirements.txt    # Python 3.10 recommended
python app.py                      # Starts WebSocket (port 8000) + HTTP (port 8003)
```
Requires FFmpeg installed on the system.

### Java Admin API (manager-api)
```bash
cd main/manager-api
mvn spring-boot:run                # Starts on port 8002, Swagger at /xiaozhi/doc.html
mvn test                           # Tests (skipped by default in build)
```
Java 21, Spring Boot 3.4.3, MyBatis Plus, Shiro auth, Liquibase migrations. Context path is `/xiaozhi`, supports up to 1000 concurrent connections.

### Web Admin Console (manager-web)
```bash
cd main/manager-web
npm install
npm run serve                      # Dev server on port 8001, proxies /xiaozhi to :8002
npm run build                      # Production build
```
Vue 2.6 + Element UI.

### Mobile Admin Console (manager-mobile)
```bash
cd main/manager-mobile
pnpm install
pnpm dev:h5                        # Dev server (H5 mode)
pnpm build:h5                      # Production build (H5)
```
UniApp 3.4 + Vue 3 + TypeScript. Uses pnpm. Also supports WeChat mini-program, iOS, and Android builds.

### Performance Testing
```bash
cd main/xiaozhi-server
python performance_tester.py       # Interactive menu for ASR/LLM/TTS/VLLM tests
```

### Docker
```bash
cd main/xiaozhi-server
docker-compose up -d               # Minimal deployment
docker-compose -f docker-compose_all.yml up -d  # Full deployment with MySQL + Redis
```

## Architecture

### Component Layout
```
main/
├── xiaozhi-server/     # Python async server (core)
├── manager-api/        # Java Spring Boot admin REST API
├── manager-web/        # Vue.js web admin console (Vue 2)
└── manager-mobile/     # Vue.js mobile admin console (UniApp + Vue 3)
```

### Python Server Core (`main/xiaozhi-server/`)

**Entry point:** `app.py` — loads config, starts WebSocket server (port 8000) and HTTP server (port 8003).

**Connection handling:** `core/connection.py` is the central hub — manages per-device WebSocket connections, audio streams, module initialization, and orchestrates the ASR→LLM→TTS pipeline. Each connected device gets its own `ConnectionHandler` instance with independent state.

**WebSocket authentication** (`core/websocket_server.py`): Multi-layer auth — device whitelist (`allowed_devices`), JWT Bearer Token, device-id + client-id headers. Auth failures return explicit error codes.

**Provider pattern:** AI services follow a factory pattern with `create_instance(type, config)`. Each provider category has a `base.py` interface and concrete implementations:
- **ASR** (`core/providers/asr/`): FunASR (local), Aliyun, Baidu, Doubao, OpenAI, Xunfei, sherpa-onnx, Vosk, Tencent, Qwen3
- **TTS** (`core/providers/tts/`): Edge TTS (default), Aliyun, Doubao, FishSpeech, GPT-SoVITS, Minimax, OpenAI, SiliconFlow, 火山, CozeCN, custom audio files
- **LLM** (`core/providers/llm/`): OpenAI-compatible (default), Gemini, Ollama, Xinference, Coze, Dify, FastGPT, Home Assistant
- **VAD** (`core/providers/vad/`): Silero
- **Memory** (`core/providers/memory/`): Mem0AI, PowerMem, local short-term, report-only, none
- **Vision/VLLM** (`core/providers/vllm/`): OpenAI
- **Intent** (`core/providers/intent/`): Function call, LLM-based, none

**Message handling chain** (`core/handle/`):
- `connection.py` dispatches to handlers based on message type
- `textMessageHandlerRegistry.py` routes text messages to type-specific handlers (hello, abort, listen, iot, mcp, server, ping)
- `receiveAudioHandle.py` / `sendAudioHandle.py` manage audio I/O

**Tool/Plugin system** (`core/providers/tools/` and `plugins_func/`):
- `UnifiedToolHandler` manages tool execution across 5 executor types: ServerPlugin, ServerMCP, DeviceIoT, DeviceMCP, MCPEndpoint
- `ToolType` enum: NONE, WAIT, CHANGE_SYS_PROMPT, SYSTEM_CTL, IOT_CTL, MCP_CLIENT
- `Action` enum defines post-tool behavior: NONE, RESPONSE, REQLLM
- Plugins in `plugins_func/functions/` are auto-discovered via `loadplugins.auto_import_modules()` — add a new .py file there to register a plugin
- Plugin functions use the `Action`/`ActionResponse` pattern from `register.py`

**Built-in plugins:** weather, news (ChinaNews/NewsNow), time, Home Assistant (init/get/set/play music), RAGFlow knowledge base search, music playback, role switching, exit handling

**Dialogue management** (`core/utils/dialogue.py`):
- `Dialogue` class manages conversation history with smart truncation (preserves tool call chains)
- `Message` class supports temporary messages, speaker identity, and tool results
- System prompts support template variables: `{{current_time}}`, `<memory>` tag injection

### Configuration

Config loading priority: `data/.config.yaml` (user overrides) → `config.yaml` (defaults). Never modify `config.yaml` directly. When using the admin console (智控台), all config is managed through the web UI.

The `selected_module` section in config determines which provider implementation is active for each category (ASR, TTS, LLM, etc.). Config supports hot-reload — the server can update modules at runtime without restart.

When `read_config_from_api` is enabled, config is fetched asynchronously from the Java admin API (`config/config_loader.py`) with caching.

### Java Admin API

Spring Boot app with layered architecture: Controller → Service → DAO (MyBatis Plus). Uses Shiro for authentication. Database migrations via Liquibase (`src/main/resources/db/changelog/`). Key tables: `sys_user`, `sys_user_token`, `sys_params`, `sys_dict_type`, `sys_dict_data`.

## Key Protocols

- **WebSocket** (`ws://host:8000/xiaozhi/v1/`): Primary device communication, OPUS audio streaming. Requires `device-id` and `authorization` headers.
- **HTTP** (port 8003): OTA updates (`/xiaozhi/ota/`), vision analysis (`/mcp/vision/explain`)
- **MQTT**: Device commands and OTA (optional gateway)
- **UDP**: Alternative device protocol (optional gateway)

## Audio Pipeline

Audio format: OPUS, 24kHz sample rate, mono, 60ms frame duration. The pipeline flows: device audio → VAD (voice activity detection) → ASR (speech-to-text) → Intent detection → LLM (text generation) → TTS (text-to-speech) → OPUS frames back to device.

## Contributing

Per `docs/contributor_open_letter.md`: develop each feature on a new branch with a concise name. Contributors who merge 3+ valid PRs gain developer status. The project's goal is a low-cost civilian Jarvis solution with smart hardware integration.

## Testing

- Interactive browser test: open `main/xiaozhi-server/test/test_page.html` in Chrome
- Performance testers: `performance_tester_asr.py`, `performance_tester_llm.py`, `performance_tester_stream_tts.py`, `performance_tester_vllm.py`
- Java tests: JUnit 5 under `manager-api/src/test/java/` (skipped by default in Maven build)
- No Python linting or type-checking tools are configured

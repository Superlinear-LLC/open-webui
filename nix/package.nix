{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchurl,
  ffmpeg-headless,
  pythonPackages,
}:

let
  pname = "open-webui";
  version = "0.13.0";

  src = fetchFromGitHub {
    owner = "open-webui";
    repo = "open-webui";
    tag = "v${version}";
    hash = "sha256-SdRSV4boNtMQT+EH6T8F3jWIVceN64lej9t9zUxY4x0=";
  };

  frontend = buildNpmPackage rec {
    pname = "open-webui-frontend";
    inherit version src;

    # Must match the `pyodide` version resolved in the upstream package-lock.json
    # for this tag: the frontend is built against that loader, and preBuild
    # unpacks this distribution in place of the `pyodide:fetch` script that
    # postPatch strips out. Upstream pyodide switched to CPython-tracking
    # version numbers (0.28.x -> 314.x) between Open WebUI 0.10.2 and 0.11.1;
    # 0.13.0 still resolves 314.0.3.
    pyodideVersion = "314.0.3";
    pyodide = fetchurl {
      url = "https://github.com/pyodide/pyodide/releases/download/${pyodideVersion}/pyodide-${pyodideVersion}.tar.bz2";
      hash = "sha256-oCgELZDbqedP377PNuqn1X6IvwrWGNnFBZ6xBAqnYSo=";
    };

    npmDepsHash = "sha256-RghvGUP2Q6WdRGDJshfPpwuWuDTa10Wauv0evg9nKvA=";

    npmFlags = [
      "--force"
      "--legacy-peer-deps"
    ];

    # Anchor on the script's key. 0.13.0 changed `build` to call vite through
    # node with a heap flag, and the old pattern then matched `build:watch`
    # instead (its text is a substring there), so --replace-fail stayed green
    # while `build` still ran pyodide:fetch and died on PyPI inside the sandbox.
    postPatch = ''
      substituteInPlace package.json \
        --replace-fail '"build": "npm run pyodide:fetch && ' '"build": "'
    '';

    propagatedBuildInputs = [ ffmpeg-headless ];

    env.CYPRESS_INSTALL_BINARY = "0";
    env.ONNXRUNTIME_NODE_INSTALL_CUDA = "skip";
    env.NODE_OPTIONS = "--max-old-space-size=8192";

    preBuild = ''
      tar xf ${frontend.pyodide} -C static/
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share
      cp -a build $out/share/open-webui

      runHook postInstall
    '';
  };

  # Upstream 0.13.0 moved MCP transport (open_webui/utils/mcp/client.py) onto
  # pydantic's httpx2, a hard dependency pinned to 2.16.0 together with its own
  # httpcore2 2.16.0. Neither is in nixpkgs; both ship pure-Python wheels, so
  # they are taken from PyPI directly. Bump both together: httpx2 pins
  # httpcore2 to the exact same version.
  httpcore2 = pythonPackages.buildPythonPackage rec {
    pname = "httpcore2";
    version = "2.16.0";
    format = "wheel";
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/af/c2/ce417c397afa5181f0e3c6ff01a4d01639414e1adef08730d97571297151/httpcore2-${version}-py3-none-any.whl";
      hash = "sha256-XENYMZ8mAtmErZMYLJ/uUWDyLp2nur3ahwpefE4tw08=";
    };
    dependencies = with pythonPackages; [ h11 truststore anyio h2 ];
    pythonImportsCheck = [ "httpcore2" ];
    meta.license = lib.licenses.bsd3;
  };

  httpx2 = pythonPackages.buildPythonPackage rec {
    pname = "httpx2";
    version = "2.16.0";
    format = "wheel";
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/7b/3d/2e4bc4fd1ef9770871669adb348d612a6e4786b303a23f9935b81c48dd60/httpx2-${version}-py3-none-any.whl";
      hash = "sha256-/SxdeQno2G/pLVMCDDEMoOTkMbg4wgfFdUubvwMI1Jo=";
    };
    dependencies = with pythonPackages; [ httpcore2 anyio idna truststore h2 ];
    # The wheel asks for idna>=3.18; nixpkgs-unstable carries 3.11. idna's
    # releases are Unicode-table refreshes, and httpx2 only uses it to encode
    # hostnames, so the older table is accepted rather than overriding idna
    # for the whole Python set.
    pythonRelaxDeps = [ "idna" ];
    pythonImportsCheck = [ "httpx2" ];
    meta.license = lib.licenses.bsd3;
  };
in
  pythonPackages.buildPythonApplication {
  inherit pname version src;
  pyproject = true;

  # stateless-chat-null-guards.patch was dropped at 0.11.1. Upstream introduced
  # open_webui/utils/chat_id.py:is_saved_chat_id() — None-safe, and covering the
  # "temporary:" prefix the patch predated — and adopted it at the two sites that
  # actually mattered: the socket save_to_chat guard and background_tasks_handler.
  #
  # It is NOT a superset of the whole patch, and an earlier version of this
  # comment wrongly said it was. Upstream did not adopt the other half: the
  # emitter/caller factory guards (socket/main.py, and the caller in
  # functions.py) are still key-presence tests, not truthiness. So for a
  # present-but-None chat_id we now return an emitter where the patch returned
  # None. That is a behaviour change, not a defect — the body's prefix checks are
  # is_saved_chat_id() now, so such an emitter emits chat_id=None and skips the
  # database write rather than raising. Re-verify this if upstream ever
  # reintroduces a bare chat_id.startswith() in that path.
  patches = [
    ./oauth-session-preservation.patch
  ];

  build-system = [ pythonPackages.hatchling ];

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail ', build = "open_webui/frontend"' ""
  '';

  env.HATCH_BUILD_NO_HOOKS = true;

  pythonRelaxDeps = true;

  dependencies = with pythonPackages; [
    accelerate
    aiocache
    # Upstream pins aiodns==3.6.1 and warns that 4.x pulls pycares 5 (c-ares
    # 1.34.6), which breaks DNS on some hosts; nixpkgs carries 4.x and
    # pythonRelaxDeps lets it through. Only reachable when aiohttp's async
    # resolver is opted into via AIOHTTP_CLIENT_ASYNC_DNS_RESOLVER, which this
    # deployment does not set.
    aiodns
    aiofiles
    aiohttp
    aiosqlite
    alembic
    anthropic
    argon2-cffi
    asgiref
    authlib
    azure-ai-documentintelligence
    azure-identity
    azure-storage-blob
    bcrypt
    beautifulsoup4
    black
    boto3
    brotli
    brotlicffi
    chardet
    chromadb
    cryptography
    ddgs
    docx2txt
    einops
    fake-useragent
    fastapi
    faster-whisper
    ftfy
    google-cloud-storage
    google-re2
    googleapis-common-protos
    hiredis
    httpx
    httpx2
    itsdangerous
    joserfc
    langchain-classic
    langchain-core
    langchain-text-splitters
    ldap3
    loguru
    lxml
    markdown
    mcp
    msoffcrypto-tool
    onnxruntime
    openai
    opencv-python-headless
    openpyxl
    opensearch-py
    orjson
    pandas
    # pgvector and psycopg2-binary are upstream's `postgres` extra, not base
    # dependencies; this deployment runs on PostgreSQL + pgvector.
    pgvector
    pillow
    psutil
    psycopg
    psycopg2-binary
    pyarrow
    pycrdt
    pydub
    pyjwt
    pymysql
    pyotp
    pypandoc
    pydantic
    pypdf
    python-docx
    python-mimeparse
    python-multipart
    python-pptx
    python-socketio
    pytz
    pyxlsb
    qrcode
    rank-bm25
    rapidocr
    redis
    regex
    requests
    sentence-transformers
    sentencepiece
    soundfile
    sqlalchemy
    starlette-compress
    starsessions
    tiktoken
    transformers
    uvicorn
    validators
    xlrd
    youtube-transcript-api
  ]
  ++ pythonPackages.pyjwt.optional-dependencies.crypto
  ++ pythonPackages.starsessions.optional-dependencies.redis;

  pythonImportsCheck = [ "open_webui" ];

  makeWrapperArgs = [ "--set FRONTEND_BUILD_DIR ${frontend}/share/open-webui" ];

  passthru = {
    inherit frontend;
  };

  meta = {
    changelog = "https://github.com/open-webui/open-webui/blob/v${version}/CHANGELOG.md";
    description = "Comprehensive suite for LLMs with a user-friendly WebUI";
    homepage = "https://github.com/open-webui/open-webui";
    license = {
      fullName = "Open WebUI License";
      url = "https://github.com/open-webui/open-webui/blob/v${version}/LICENSE";
      free = false;
    };
    mainProgram = "open-webui";
    platforms = lib.platforms.unix;
  };
}

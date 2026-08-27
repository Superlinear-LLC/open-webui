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
  version = "0.11.1";

  src = fetchFromGitHub {
    owner = "open-webui";
    repo = "open-webui";
    tag = "v${version}";
    hash = "sha256-W3RzBYUtI32Ft1Nw5JM7Z/mgYELNAlFCJmrNa2Wnhu4=";
  };

  frontend = buildNpmPackage rec {
    pname = "open-webui-frontend";
    inherit version src;

    # Must match the `pyodide` version resolved in the upstream package-lock.json
    # for this tag: the frontend is built against that loader, and preBuild
    # unpacks this distribution in place of the `pyodide:fetch` script that
    # postPatch strips out. Upstream pyodide switched to CPython-tracking
    # version numbers (0.28.x -> 314.x) between Open WebUI 0.10.2 and 0.11.1.
    pyodideVersion = "314.0.3";
    pyodide = fetchurl {
      url = "https://github.com/pyodide/pyodide/releases/download/${pyodideVersion}/pyodide-${pyodideVersion}.tar.bz2";
      hash = "sha256-oCgELZDbqedP377PNuqn1X6IvwrWGNnFBZ6xBAqnYSo=";
    };

    npmDepsHash = "sha256-5W/IMa23b0afAlw5Md8KvJYQmRen8u1dfUG2RAKDOn0=";

    npmFlags = [
      "--force"
      "--legacy-peer-deps"
    ];

    postPatch = ''
      substituteInPlace package.json \
        --replace-fail "npm run pyodide:fetch && vite build" "vite build"
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
in
  pythonPackages.buildPythonApplication {
  inherit pname version src;
  pyproject = true;

  # stateless-chat-null-guards.patch was dropped at 0.11.1: upstream introduced
  # open_webui/utils/chat_id.py:is_saved_chat_id(), which is a strict superset of
  # what that patch guarded — it is None-safe and also covers the new
  # "temporary:" prefix the patch predated.
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
    apscheduler
    argon2-cffi
    asgiref
    async-timeout
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
    fpdf2
    ftfy
    google-api-python-client
    google-auth-httplib2
    google-auth-oauthlib
    google-cloud-storage
    google-genai
    googleapis-common-protos
    hiredis
    httpx
    itsdangerous
    joserfc
    langchain
    langchain-classic
    langchain-community
    langchain-text-splitters
    ldap3
    loguru
    lxml
    markdown
    mcp
    msoffcrypto-tool
    nltk
    onnxruntime
    openai
    opencv-python-headless
    openpyxl
    opensearch-py
    orjson
    pandas
    peewee
    peewee-migrate
    pgvector
    pillow
    psutil
    psycopg
    psycopg2-binary
    pyarrow
    pycrdt
    pydub
    pyjwt
    pymdown-extensions
    pymysql
    pypandoc
    pydantic
    pypdf
    python-docx
    python-dotenv
    python-mimeparse
    python-multipart
    python-pptx
    python-socketio
    pytube
    pytz
    pyxlsb
    rank-bm25
    rapidocr
    redis
    regex
    requests
    restrictedpython
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

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
  version = "0.10.2";

  src = fetchFromGitHub {
    owner = "open-webui";
    repo = "open-webui";
    tag = "v${version}";
    hash = "sha256-tJ9b5up5FoX5TrmpwMWevyA/o3Ai/lKsHu+nahc2Ttc=";
  };

  frontend = buildNpmPackage rec {
    pname = "open-webui-frontend";
    inherit version src;

    pyodideVersion = "0.28.3";
    pyodide = fetchurl {
      url = "https://github.com/pyodide/pyodide/releases/download/0.28.3/pyodide-0.28.3.tar.bz2";
      hash = "sha256-fcqubT8VmGoJ8PnmxHE6DA8kv/DJDHToWoFyPxvGCUA=";
    };

    npmDepsHash = "sha256-yw/1n1jBCUtt8wUqJmIkB3W53wsXTKuAFG/EMwcTpx8=";

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

  patches = [
    ./oauth-session-preservation.patch
    ./stateless-chat-null-guards.patch
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
    httpx
    itsdangerous
    langchain
    langchain-classic
    langchain-community
    langchain-text-splitters
    ldap3
    loguru
    markdown
    mcp
    msoffcrypto-tool
    nltk
    onnxruntime
    openai
    opencv-python-headless
    openpyxl
    opensearch-py
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
    python-dotenv
    python-jose
    python-mimeparse
    python-multipart
    python-pptx
    python-socketio
    pytube
    pytz
    pyxlsb
    rank-bm25
    rapidocr-onnxruntime
    redis
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

import pytest

from eyereader.llm import LLMClient, LLMError


class FakeResponse:
    def __init__(self, status_code=200, payload=None):
        self.status_code = status_code
        self._payload = payload or {}
        self.text = str(payload)

    def json(self):
        return self._payload


class FakeSession:
    def __init__(self, response):
        self.response = response
        self.calls = []

    def post(self, url, json=None, headers=None, timeout=None):
        self.calls.append({"url": url, "json": json, "headers": headers})
        return self.response


def ok(content):
    return FakeResponse(payload={"choices": [{"message": {"content": content}}]})


def last_prompt(session):
    return session.calls[-1]["json"]["messages"][-1]["content"]


def test_default_is_free_local_ollama(monkeypatch):
    for var in ("EYEREADER_LLM_URL", "EYEREADER_LLM_MODEL", "EYEREADER_LLM_KEY"):
        monkeypatch.delenv(var, raising=False)
    client = LLMClient(session=FakeSession(ok("hi")))
    assert client.base_url == "http://localhost:11434/v1"
    assert client.model == "llama3.2"
    assert client.api_key is None


def test_other_free_services_can_be_chosen_by_environment(monkeypatch):
    monkeypatch.setenv("EYEREADER_LLM_URL", "https://api.groq.com/openai/v1/")
    monkeypatch.setenv("EYEREADER_LLM_MODEL", "m1")
    monkeypatch.setenv("EYEREADER_LLM_KEY", "secret")
    session = FakeSession(ok("x"))
    LLMClient(session=session).chat("q")
    assert session.calls[0]["url"] == "https://api.groq.com/openai/v1/chat/completions"
    assert session.calls[0]["json"]["model"] == "m1"
    assert session.calls[0]["headers"]["Authorization"] == "Bearer secret"


def test_chat_sends_openai_compatible_request_and_returns_answer():
    session = FakeSession(ok("  안녕하세요  "))
    assert LLMClient(base_url="http://x/v1", session=session).chat("hello") == "안녕하세요"
    assert session.calls[0]["json"]["messages"][-1] == {"role": "user", "content": "hello"}
    assert "Authorization" not in session.calls[0]["headers"]


def test_http_error_raises_llm_error():
    with pytest.raises(LLMError):
        LLMClient(session=FakeSession(FakeResponse(500, {"error": "boom"}))).chat("q")


def test_unexpected_response_raises_llm_error():
    with pytest.raises(LLMError):
        LLMClient(session=FakeSession(FakeResponse(200, {"nope": 1}))).chat("q")


def test_connection_failure_raises_llm_error():
    class Broken:
        def post(self, *a, **k):
            raise ConnectionError("refused")

    with pytest.raises(LLMError):
        LLMClient(session=Broken()).chat("q")


def test_summarize_sends_page_text():
    session = FakeSession(ok("요약"))
    assert LLMClient(session=session).summarize("The cat sat.") == "요약"
    assert "The cat sat." in last_prompt(session)


def test_explain_sends_word_and_context():
    session = FakeSession(ok("뜻"))
    LLMClient(session=session).explain("serendipity", context="It was serendipity.")
    assert "serendipity" in last_prompt(session) and "It was serendipity." in last_prompt(session)

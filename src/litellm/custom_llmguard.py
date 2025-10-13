from __future__ import annotations
from typing import Any, AsyncGenerator, Dict, List, Literal, Optional, Tuple, Union
import os, json, urllib.request, urllib.error
import uuid
import asyncio

import litellm
from litellm._logging import verbose_proxy_logger
from litellm.caching.caching import DualCache
from litellm.integrations.custom_guardrail import CustomGuardrail
from litellm.proxy._types import UserAPIKeyAuth
from litellm.types.utils import ModelResponseStream

JSON = Dict[str, Any]

LLMGUARD_API_BASE = os.environ.get("LLMGUARD_API_BASE", "http://llmguard:4321")
LLMGUARD_API_TOKEN = os.environ.get("LLMGUARD_API_TOKEN")  # optional shared secret header

def _iter_user_contents(request_data: JSON) -> List[Tuple[int, int, str]]:
    out: List[Tuple[int, int, str]] = []
    msgs = request_data.get("messages") or []
    for mi, msg in enumerate(msgs):
        if msg.get("role") != "user":
            continue
        content = msg.get("content")
        if isinstance(content, str):
            out.append((mi, -1, content))
        elif isinstance(content, list):
            for ci, c in enumerate(content):
                if isinstance(c, dict) and c.get("type") == "text" and isinstance(c.get("text"), str):
                    out.append((mi, ci, c["text"]))
    return out

def _write_back_user_content(request_data: JSON, idxs: List[Tuple[int, int, str]]) -> None:
    msgs = request_data.get("messages") or []
    for mi, ci, new_text in idxs:
        if ci == -1:
            msgs[mi]["content"] = new_text
        else:
            msgs[mi]["content"][ci]["text"] = new_text

def _sync_post(url: str, payload: dict) -> dict:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    if LLMGUARD_API_TOKEN:
        req.add_header("X-LLMGUARD-TOKEN", LLMGUARD_API_TOKEN)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))

async def _post_json(url: str, payload: dict) -> dict:
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(None, _sync_post, url, payload)

class LLMGuardRail(CustomGuardrail):
    def __init__(self, **kwargs):
        # Tunables passed from config.yaml
        self.pi_threshold: float = float(kwargs.get("pi_threshold", 0.85))
        self.tox_threshold: float = float(kwargs.get("tox_threshold", 0.92))
        self.sensitive_threshold: float = float(kwargs.get("sensitive_threshold", 0.50))
        self.fail_on_injection: bool = bool(kwargs.get("fail_on_injection", True))
        self.fail_on_secrets: bool = bool(kwargs.get("fail_on_secrets", True))
        super().__init__(**kwargs)

    async def async_pre_call_hook(
        self,
        user_api_key_dict: UserAPIKeyAuth,
        cache: DualCache,
        data: JSON,
        call_type: Literal[
            "completion",
            "text_completion",
            "embeddings",
            "image_generation",
            "moderation",
            "audio_transcription",
            "pass_through_endpoint",
            "rerank",
        ],
    ) -> Optional[Union[Exception, str, dict]]:
        # Assign a vault_id for this request and store in metadata so post hook can reuse it
        meta = data.setdefault("metadata", {})
        vault_id = meta.get("llmguard_vault_id") or str(uuid.uuid4())
        meta["llmguard_vault_id"] = vault_id

        user_texts = _iter_user_contents(data)
        updated: List[Tuple[int, int, str]] = []
        blocked_reasons: List[str] = []

        for mi, ci, text in user_texts:
            payload = {
                "text": text,
                "vault_id": vault_id,
                "pi_threshold": self.pi_threshold,
                "use_onnx": True,
            }
            try:
                resp = await _post_json(f"{LLMGUARD_API_BASE}/scan/prompt", payload)
            except urllib.error.URLError as e:
                return ValueError(f"LLMGuard API error (prompt): {e}")

            if not isinstance(resp, dict) or "sanitized_text" not in resp:
                return ValueError("LLMGuard API: unexpected response for prompt scan")

            if not resp.get("valid", True):
                # We can choose to block on injection or secrets only
                reasons = resp.get("reasons", [])
                if self.fail_on_injection or self.fail_on_secrets:
                    blocked_reasons.extend(reasons)

            updated.append((mi, ci, resp["sanitized_text"]))

        if blocked_reasons:
            return ValueError(f"LLMGuard: input rejected ({', '.join(blocked_reasons)})")

        _write_back_user_content(data, updated)
        return data

    async def async_moderation_hook(
        self,
        data: dict,
        user_api_key_dict: UserAPIKeyAuth,
        call_type: Literal[
            "completion",
            "embeddings",
            "image_generation",
            "moderation",
            "audio_transcription",
        ],
    ):
        # Quick parallel re-check; we won't modify content here
        meta = data.get("metadata") or {}
        vault_id = meta.get("llmguard_vault_id") or str(uuid.uuid4())
        for _, _, text in _iter_user_contents(data):
            payload = {"text": text, "vault_id": vault_id, "pi_threshold": self.pi_threshold, "use_onnx": True}
            try:
                resp = await _post_json(f"{LLMGUARD_API_BASE}/scan/prompt", payload)
            except urllib.error.URLError as e:
                raise ValueError(f"LLMGuard API error (during): {e}")
            if not resp.get("valid", True):
                raise ValueError(f"LLMGuard: during_call rejected ({', '.join(resp.get('reasons', []))})")

    async def async_post_call_success_hook(
        self,
        data: dict,
        user_api_key_dict: UserAPIKeyAuth,
        response: Union[litellm.ModelResponse, Any],
    ):
        if not isinstance(response, litellm.ModelResponse):
            return
        meta = data.get("metadata") or {}
        vault_id = meta.get("llmguard_vault_id") or str(uuid.uuid4())

        for choice in response.choices:
            if not isinstance(choice, litellm.Choices):
                continue
            content = getattr(choice.message, "content", None)
            if not isinstance(content, str):
                continue

            payload = {
                "text": content,
                "vault_id": vault_id,
                "tox_threshold": self.tox_threshold,
                "sensitive_threshold": self.sensitive_threshold,
                "use_onnx": True,
            }
            try:
                resp = await _post_json(f"{LLMGUARD_API_BASE}/scan/output", payload)
            except urllib.error.URLError as e:
                raise ValueError(f"LLMGuard API error (output): {e}")

            if not isinstance(resp, dict) or "final_text" not in resp:
                raise ValueError("LLMGuard API: unexpected response for output scan")

            if not resp.get("valid", True):
                raise ValueError(f"LLMGuard: output rejected ({', '.join(resp.get('reasons', []))})")

            choice.message.content = resp["final_text"]  # deanonymized/sanitized

    async def async_post_call_streaming_iterator_hook(
        self,
        user_api_key_dict: UserAPIKeyAuth,
        response: Any,
        request_data: dict,
    ) -> AsyncGenerator[ModelResponseStream, None]:
        async for item in response:
            yield item
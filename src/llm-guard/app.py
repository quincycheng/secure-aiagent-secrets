
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel
from typing import Dict, Optional, List, Any
import os
import yaml
import traceback

from llm_guard import input_scanners, output_scanners
from llm_guard.vault import Vault

CONFIG_PATH = os.environ.get("LLMGUARD_CONFIG_PATH", "scanner_config.yaml")
with open(CONFIG_PATH, "r") as f:
    SCANNER_CONFIG = yaml.safe_load(f)

app = FastAPI(title="llm-guard-api", version="1.0.0")

_VAULTS: Dict[str, Vault] = {}
API_TOKEN = os.environ.get("LLMGUARD_API_TOKEN")

def get_vault(vault_id: str) -> Vault:
    if vault_id not in _VAULTS:
        print(f"[Vault] Creating new vault for ID: {vault_id}")
        _VAULTS[vault_id] = Vault()
    return _VAULTS[vault_id]

def check_auth(header: Optional[str]):
    if API_TOKEN and header != API_TOKEN:
        print("[Auth] Authorization failed")
        raise HTTPException(status_code=401, detail="Unauthorized")

class PromptScanReq(BaseModel):
    text: str
    vault_id: Optional[str] = "default"

class PromptScanResp(BaseModel):
    sanitized_text: str
    valid: bool
    reasons: List[str] = []
    scores: Dict[str, Any] = {}

class OutputScanReq(BaseModel):
    text: str
    vault_id: Optional[str] = "default"

class OutputScanResp(BaseModel):
    final_text: str
    valid: bool
    reasons: List[str] = []
    scores: Dict[str, Any] = {}

@app.get("/healthz")
def healthz():
    print("[Health] Health check requested")
    return {"status": "ok"}

@app.post("/scan/prompt", response_model=PromptScanResp)
def scan_prompt(req: PromptScanReq, x_llmguard_token: Optional[str] = Header(default=None)):
    print(f"[PromptScan] Received request: {req}")
    check_auth(x_llmguard_token)
    vault = get_vault(req.vault_id)

    scanners = {}
    reasons, scores = [], {}
    text = req.text

    try:
        for name in ["PromptInjection", "Secrets", "Anonymize"]:
            cfg = SCANNER_CONFIG["input_scanners"].get(name, {})
            if cfg.get("enabled", True):
                params = cfg.get("params", {})
                if "vault" in params:
                    params["vault"] = vault
                scanners[name] = input_scanners.get_scanner_by_name(name, params)

        if "PromptInjection" in scanners:
            text, ok_pi, sc_pi = scanners["PromptInjection"].scan(text)
            scores["prompt_injection"] = sc_pi
            if not ok_pi:
                reasons.append(f"prompt_injection(score={sc_pi:.2f})")

        if "Secrets" in scanners:
            text, ok_sec, sc_sec = scanners["Secrets"].scan(text)
            scores["secrets"] = sc_sec
            if not ok_sec:
                reasons.append(f"secrets(score={sc_sec:.2f})")

        if "Anonymize" in scanners:
            text, _, _ = scanners["Anonymize"].scan(text)

    except Exception as e:
        print(f"[PromptScan] Error: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

    print(f"[PromptScan] Sanitized text: {text}")
    valid = len(reasons) == 0
    return PromptScanResp(sanitized_text=text, valid=valid, reasons=reasons, scores=scores)

@app.post("/scan/output", response_model=OutputScanResp)
def scan_output(req: OutputScanReq, x_llmguard_token: Optional[str] = Header(default=None)):
    print(f"[OutputScan] Received request: {req}")
    check_auth(x_llmguard_token)
    vault = get_vault(req.vault_id)

    scanners = {}
    reasons, scores = [], {}
    text = req.text

    try:
        for name in ["Toxicity", "MaliciousURLs", "Sensitive", "Deanonymize"]:
            cfg = SCANNER_CONFIG["output_scanners"].get(name, {})
            if cfg.get("enabled", True):
                params = cfg.get("params", {})
                if "vault" in params:
                    params["vault"] = vault
                scanners[name] = output_scanners.get_scanner_by_name(name, params)

        try:
            if "Toxicity" in scanners:
                _, ok_tox, sc_tox = scanners["Toxicity"].scan(text, text)
                scores["toxicity"] = sc_tox
                if not ok_tox:
                    reasons.append(f"toxicity(score={sc_tox:.2f})")
        except Exception as e:
            print(f"[Toxicity] Scanner failed: {e}")
            traceback.print_exc()

        try:
            if "MaliciousURLs" in scanners:
                _, ok_url, sc_url = scanners["MaliciousURLs"].scan(text)
                scores["malicious_urls"] = sc_url
                if not ok_url:
                    reasons.append(f"malicious_urls(score={sc_url:.2f})")
        except Exception as e:
            print(f"[MaliciousURLs] Scanner failed: {e}")
            traceback.print_exc()

        try:
            if "Sensitive" in scanners:
                _, ok_sens, sc_sens = scanners["Sensitive"].scan(text)
                scores["sensitive"] = sc_sens
                if not ok_sens:
                    reasons.append(f"sensitive(score={sc_sens:.2f})")
        except Exception as e:
            print(f"[Sensitive] Scanner failed: {e}")
            traceback.print_exc()

        try:
            if "Deanonymize" in scanners:
                text, _, _ = scanners["Deanonymize"].scan(text)
        except Exception as e:
            print(f"[Deanonymize] Scanner failed: {e}")
            traceback.print_exc()

    except Exception as e:
        print(f"[OutputScan] Error: {e}")
        traceback.print_exc()
        return OutputScanResp(final_text=text, valid=False, reasons=["Internal error"], scores=scores)

    print(f"[OutputScan] Final output text: {text}")
    valid = len(reasons) == 0
    return OutputScanResp(final_text=text, valid=valid, reasons=reasons, scores=scores)

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel
from typing import Dict, Optional, List, Any
import os
import torch

from llm_guard import input_scanners, output_scanners
from llm_guard.vault import Vault

# Determine device: GPU if available, else CPU
#DEVICE = os.environ.get("LLMGUARD_DEVICE", "cuda" if torch.cuda.is_available() else "cpu")
#DEVICE = "cuda"
#print(f"[Init] Using device: {DEVICE}")

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
    pi_threshold: float = 0.85

class PromptScanResp(BaseModel):
    sanitized_text: str
    valid: bool
    reasons: List[str] = []
    scores: Dict[str, Any] = {}

class OutputScanReq(BaseModel):
    text: str
    vault_id: Optional[str] = "default"
    tox_threshold: float = 0.92
    sensitive_threshold: float = 0.50

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

    try:
        print("[PromptScan] Initializing scanners")
        s_prompt_injection = input_scanners.get_scanner_by_name(
            "PromptInjection", {"threshold": req.pi_threshold}
        )
        s_secrets = input_scanners.get_scanner_by_name("Secrets", {})
        s_anonymize = input_scanners.get_scanner_by_name("Anonymize", {"vault": vault})
    except Exception as e:
        print(f"[PromptScan] Scanner init error: {e}")
        raise HTTPException(status_code=500, detail=f"Scanner initialization failed: {str(e)}")

    reasons, scores = [], {}
    text = req.text

    try:
        print("[PromptScan] Running PromptInjection scan")
        text, ok_pi, sc_pi = s_prompt_injection.scan(text)
        scores["prompt_injection"] = sc_pi
        if not ok_pi:
            reasons.append(f"prompt_injection(score={sc_pi:.2f})")

        print("[PromptScan] Running Secrets scan")
        text, ok_sec, sc_sec = s_secrets.scan(text)
        scores["secrets"] = sc_sec
        if not ok_sec:
            reasons.append(f"secrets(score={sc_sec:.2f})")

        print("[PromptScan] Running Anonymize scan")
        text, _, _ = s_anonymize.scan(text)
    except Exception as e:
        print(f"[PromptScan] Scanning error: {e}")
        raise HTTPException(status_code=500, detail=f"Scanning failed: {str(e)}")

    valid = len(reasons) == 0
    print(f"[PromptScan] Completed. Valid: {valid}, Reasons: {reasons}")
    return PromptScanResp(sanitized_text=text, valid=valid, reasons=reasons, scores=scores)

@app.post("/scan/output", response_model=OutputScanResp)
def scan_output(req: OutputScanReq, x_llmguard_token: Optional[str] = Header(default=None)):
    print(f"[OutputScan] Received request: {req}")
    check_auth(x_llmguard_token)
    vault = get_vault(req.vault_id)

    try:
        print("[OutputScan] Initializing scanners")
        s_toxic = output_scanners.get_scanner_by_name(
            "Toxicity", {"threshold": req.tox_threshold}
        )
        s_malurls = output_scanners.get_scanner_by_name("MaliciousURLs", {})
        s_sensitive = output_scanners.get_scanner_by_name(
            "Sensitive", {"threshold": req.sensitive_threshold}
        )
        s_deanon = output_scanners.get_scanner_by_name("Deanonymize", {"vault": vault})
    except Exception as e:
        print(f"[OutputScan] Scanner init error: {e}")
        raise HTTPException(status_code=500, detail=f"Scanner initialization failed: {str(e)}")

    reasons, scores = [], {}
    text = req.text

    try:
        print("[OutputScan] Running Toxicity scan")
        _, ok_tox, sc_tox = s_toxic.scan(text, text)
        scores["toxicity"] = sc_tox
        if not ok_tox:
            reasons.append(f"toxicity(score={sc_tox:.2f})")

        print("[OutputScan] Running MaliciousURLs scan")
        _, ok_url, sc_url = s_malurls.scan(output=text)
        scores["malicious_urls"] = sc_url
        if not ok_url:
            reasons.append(f"malicious_urls(score={sc_url:.2f})")

        print("[OutputScan] Running Sensitive scan")
        _, ok_sens, sc_sens = s_sensitive.scan(output=text)
        scores["sensitive"] = sc_sens
        if not ok_sens:
            reasons.append(f"sensitive(score={sc_sens:.2f})")

        print("[OutputScan] Running Deanonymize scan")
        text, _, _ = s_deanon.scan(output=text)
    except Exception as e:
        print(f"[OutputScan] Scanning error: {e}")
        raise HTTPException(status_code=500, detail=f"Scanning failed: {str(e)}")

    valid = len(reasons) == 0
    print(f"[OutputScan] Completed. Valid: {valid}, Reasons: {reasons}")

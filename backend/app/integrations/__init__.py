"""Clients for external services (Supabase, and future OCR/LLM providers).

Kept separate from ``app.core`` (framework/cross-cutting concerns) and ``app.api``
(HTTP layer): everything here talks to a third party over the network.
"""

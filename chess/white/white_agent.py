"""
White Chess Agent (SSE transport)
"""

import os
import chess
import logging
from mcp.server.fastmcp import FastMCP
from autogen_agentchat.agents import AssistantAgent
from autogen_ext.models.openai import AzureOpenAIChatCompletionClient
from dotenv import load_dotenv

load_dotenv()


logging.basicConfig(level=logging.INFO, format="[WhiteAgent] %(message)s")
log = logging.getLogger(__name__)

board = chess.Board()

mcp = FastMCP(name="White Chess Agent",
              description="White chess agent using SSE transport",
              base_url="http://localhost:8001",

              describe_all_responses=True,  # Include all possible response schemas
              describe_full_response_schema=True)  # Include full JSON schema in descriptions)

client = AzureOpenAIChatCompletionClient(
    model="gpt-4o",
    azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
    azure_deployment=os.getenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4o"),
    api_version="2024-02-15-preview",
)
agent = AssistantAgent(
    name="white_player",
    model_client=client,
    description="""You are a chess player, playing with white pieces. 
                    Before you decide about a next move, you must analyze the current 
                    board state and provide a legal best move in UCI notation. 
                    Provide LEGAL MOVES in UCI notation only.
                    Double check and reason about the selected move before sending it. 
                    Your goal is to win the game.""",
    system_message=(
        "You play WHITE. Respond only with one legal UCI move (e.g. e2e4) for the given FEN."
    ),
)

@mcp.tool(
    name="move",
    description="Return a legal white move in UCI for the provided FEN.",
)
async def move_tool(fen: str):
    """Return next white move (UCI)."""
    log.info(f"[WhiteAgent] Received move request. FEN: {fen}")
    
    # Verify that we got a valid FEN string, not a UCI move
    if len(fen.split()) < 4 or '/' not in fen:
        log.error(f"[WhiteAgent] ERROR: Invalid FEN format: {fen}")
        return {"error": f"Invalid input: expected FEN position string, got '{fen}'"}
    
    try:
        board.set_fen(fen)
    except ValueError as e:
        log.error(f"[WhiteAgent] ERROR: Cannot set board from FEN: {e}")
        return {"error": f"Invalid FEN: {str(e)}"}
    
    # Make sure it's white's turn in this position
    if not board.turn:
        log.info("[WhiteAgent] ERROR: It's black's turn in this position, but I'm the white player")
        return {"error": "It's not white's turn in this position"}
    
    prompt = f"You are white. Current board FEN: {fen}. Provide one legal move in UCI only."
    resp = await agent.run(task=prompt)
    uci_raw = resp.messages[-1].content   # e.g. "e2e4 TERMINATE"
    uci = uci_raw.split()[0]              # take first token → "e2e4"
    log.info("[WhiteAgent] LLM suggested: %s", uci)
    
    # Validate the UCI move
    try:
        mv = chess.Move.from_uci(uci)
        if mv not in board.legal_moves:
            log.info("[WhiteAgent] Illegal move detected -> %s", uci)
            return {"error": f"illegal move {uci}"}
    except ValueError:
        log.error(f"[WhiteAgent] Invalid UCI format: {uci}")
        return {"error": f"Invalid UCI move format: {uci}"}
        
    log.info("[WhiteAgent] Move accepted -> %s", uci)
    return {"uci": uci}

if __name__ == "__main__":
    log.info("Starting White Player Agent...")
    mcp.run(transport='sse')

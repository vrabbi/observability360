# ──────────────────────────────────────────────
# 1.black_agent.py
# ──────────────────────────────────────────────
"""Black Pieces Player Chess Agent (SSE transport). Start with:
    
"""
import os
import sys
import chess
import logging
from mcp.server.fastmcp import FastMCP
from autogen_agentchat.agents import AssistantAgent
from autogen_ext.models.openai import AzureOpenAIChatCompletionClient
from otel.otel import configure_telemetry
from dotenv import load_dotenv
load_dotenv()


SERVICE_VERSION = "1.0.0"

instruments = configure_telemetry("Black", SERVICE_VERSION)
meter = instruments["meter"]
tracer = instruments["tracer"]
log = instruments["logger"]

MAX_NUMBER_OF_RETRIES = 5
#logging.basicConfig(level=logging.INFO, format="[BlackAgent] %(message)s")
#log = logging.getLogger(__name__)


mcp = FastMCP(name="Black Pieces Chess Agent",
              description="Black pieces chess agent using SSE transport",
              base_url="http://localhost:8000",
              describe_all_responses=True,  # Include all possible response schemas
              describe_full_response_schema=True)  # Include full JSON schema in descriptions)

client = AzureOpenAIChatCompletionClient(
    model=os.getenv("AZURE_OPENAI_MODEL", "gpt-4o"),
    azure_endpoint=os.getenv("AZURE_OPENAI_ENDPOINT"),
    azure_deployment=os.getenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4o"),
    api_version= os.getenv("AZURE_OPENAI_API_VERSION", "2025-01-01-preview"),
)

agent = AssistantAgent(
    name="black_pieces_player",
    model_client=client,
    description="""You are a chess player, playing with BLACK pieces. 
                    Before you decide about a next move, you must analyze the current 
                    board state and provide a legal best move in UCI notation. 
                    Provide LEGAL MOVES in UCI notation only.
                    Double check and reason about the selected move before sending it. 
                    Your goal is to win the game.""",
    system_message=
        """
            You are a world-renowned chess grandmaster. You play BLACK.
            Respond only with one legal UCI move (e.g. e7e5) for the given FEN.
            You must output exactly ONE move in Universal Chess Interface (UCI) format:
                • four characters like e2e4, or
                • five if promotion, e.g. e7e8q
                No capture symbol (x), no checks (+/#), no words. Output ONLY the move.
            Double-check the move is legal in the current position.
            Do not make stupid moves!
            Follow these basic rules:
            • Prevent the most common blunder (self-check).
            • Avoid pointless sacrifices.
            • Stop discovered checks / loss of the queen.
            • Bishops, rooks and queens cannot jump over pieces.
            • Pawns never move backwards or capture straight ahead.
            • Your move must remove any check to your own king. If not, try again.
        """)

@mcp.tool(
    name="move",
    description="Return a legal black move in UCI for the provided FEN.",
)
async def move_tool(fen: str):
    """Return ONE legal black move in UCI."""
    log.info("[BlackAgent] Received FEN %s", fen)

    # 1─ Parse FEN 
    try:
        board = chess.Board(fen)       # fresh board per request
    except ValueError as e:
        log.error("[BlackAgent] Invalid FEN: %s", e)
        return {"error": f"Invalid FEN: {e}"}

    if board.turn:
        # True → White to move
        log.error("[BlackAgent] It's not black's turn")
        return {"error": "It's not black's turn"}

    # 2─ Build the legal-move menu
    legal_uci = [m.uci() for m in board.legal_moves]
    if not legal_uci:
        return {"error": "no legal moves"}
    
    with tracer.start_as_current_span("move_black_span") as span:
        #add attributes to span
        span.set_attribute("current fen", fen)
        
        prompt = (
            f"You are Black. FEN: {fen}\n"
            "Choose ONE BEST move from this list and output it **exactly**:\n"
            + ", ".join(legal_uci)
        )

        # 3─ Up to MAX_NUMBER_OF_RETRIES attempts to get a legal reply
        for _ in range(MAX_NUMBER_OF_RETRIES):
            resp = await agent.run(task=prompt)
            uci = resp.messages[-1].content.strip().split()[0].lower()

            if uci in legal_uci:
                log.info("[BlackAgent] Accepted move: %s", uci)
                span.set_attribute(f"Accepted move: {uci}")
                return {"uci": uci}

            # feedback for retry
            prompt = (
                f"That move:{uci} is not in the list or is illegal. "
                "Pick ONE move from: " + ", ".join(legal_uci)
            )

        # 4─ Give up after MAX_NUMBER_OF_RETRIES bad tries
        log.error("[BlackAgent] Too many illegal replies: %s", uci)
        return {"error": f"illegal move {uci}"}

if __name__ == "__main__":
    # mcp is your FastMCP instance
    mcp.run(transport='sse')

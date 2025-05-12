# board_orchestrator_sse.py
"""
SSE-based orchestrator for a two-engine chess game:

  • Connects to white_agent_sse.py and black_agent_sse.py via HTTP/SSE
  • Calls their `move` tool alternately, validates the moves,
    maintains a python-chess board, renders a tiny GUI,
    and logs all events.

Requires:
    pip3 install autogen-agentchat autogen-ext[openai,mcp] python-chess chess-board rich
"""

import asyncio
import json
import os
import logging
import chess
import chess.pgn
from chessboard import display
from autogen_ext.tools.mcp import McpWorkbench, SseServerParams

# configure logging
logging.basicConfig(
    level=logging.INFO,
    format="[Board] %(asctime)s %(levelname)s: %(message)s",
    datefmt="%H:%M:%S"
)
log = logging.getLogger("board")

# endpoints for SSE agents
WHITE_URL = os.getenv("WHITE_URL", "http://9.223.138.20")
BLACK_URL = os.getenv("BLACK_URL", "http://9.223.63.147")

# Board customization options (if supported by display)
BOARD_SIZE = os.getenv("BOARD_SIZE", None)  # optional
DARK_SQUARE_COLOR = os.getenv("DARK_SQUARE_COLOR", None)
LIGHT_SQUARE_COLOR = os.getenv("LIGHT_SQUARE_COLOR", None)
HIGHLIGHT_COLOR = os.getenv("HIGHLIGHT_COLOR", None)


async def run() -> None:
    board = chess.Board()
    # initialize UI with the starting FEN
    game_board = display.start(board.fen())

    # configure SSE workbenches
    wb_white = McpWorkbench(
        SseServerParams(url=f"{WHITE_URL}/sse", timeout=90)
    )
    wb_black = McpWorkbench(
        SseServerParams(url=f"{BLACK_URL}/sse", timeout=90)
    )

    async with wb_white, wb_black:
        current_wb, current_name = wb_white, "white"
        other_wb, other_name     = wb_black, "black"
        max_invalid = 10
        invalid_count = 0

        while not board.is_game_over():
            fen = board.fen()
            log.info(f"Requesting {current_name} move. FEN={fen}")

            # call the remote move tool
            result = await current_wb.call_tool("move", {"fen": fen})
            # parse SSE chunked response
            content = result.result[0].content
            print("type tool result :", content)
            if not content or 'uci' not in content:
                invalid_count += 1
                log.warning(f"{current_name} agent error ({invalid_count}/{max_invalid}): {content}")
                if invalid_count  <= max_invalid:
                    asyncio.sleep(1)
                    continue
                else:
                    log.error("Too many invalid moves; aborting game.")
                    break
            invalid_count = 0
                
            try:
                payload = json.loads(content)
            except json.JSONDecodeError:
                log.error(f"Fatal Error: Invalid JSON from {current_name}: {content}")
                break

            if not payload or 'uci' not in payload:
                invalid_count += 1
                log.warning(f"{current_name} agent error ({invalid_count}/{max_invalid}): {payload}")
                if invalid_count > max_invalid:
                    log.error("Too many invalid moves; aborting game.")
                    break
                continue
            
            invalid_count = 0
            uci = payload['uci']
            log.info(f"Received UCI from {current_name}: {uci}")

            # validate move
            try:
                mv = chess.Move.from_uci(uci)
                if mv not in board.legal_moves:
                    raise ValueError("illegal move")
            except Exception as e:
                log.error(f"Illegal move from {current_name}: {uci} ({e})")
                break

            # apply and render
            board.push(mv)
            display.update(board.fen(), game_board)
            log.info(f"Applied move {uci}")
           
            # swap turns
            current_wb, other_wb       = other_wb, current_wb
            current_name, other_name   = other_name, current_name
            await asyncio.sleep(1)

    # game over summary
    result = board.result()
    reason = ("Checkmate" if board.is_checkmate() else
              "Stalemate" if board.is_stalemate() else
              "Insufficient material" if board.is_insufficient_material() else
              "Fifty-move rule" if board.can_claim_fifty_moves() else
              "Threefold repetition" if board.can_claim_threefold_repetition() else
              "Unknown")
    log.info(f"Game over: {result} - {reason}")

    display.terminate(game_board)
    await asyncio.sleep(2)

if __name__ == "__main__":
    log.info("Starting Board Orchestrator (SSE)!")
    asyncio.run(run())

# Standard library only, same as the yield scout. chain.py talks to a BSC RPC
# over plain urllib, so the only configuration is BSC_RPC_HTTP.
FROM python:3.12-slim

WORKDIR /app
COPY chain.py keeper.py server.py ./

CMD ["python3", "server.py"]

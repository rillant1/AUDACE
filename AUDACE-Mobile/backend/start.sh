#!/bin/bash
# Démarrage complet du backend AUDACE
echo "▶ Démarrage MongoDB..."
sudo systemctl start mongod

echo "▶ Démarrage du serveur Express..."
cd "$(dirname "$0")"
node server.js &
SERVER_PID=$!
sleep 2

echo "▶ Démarrage du tunnel ngrok..."
ngrok http 5000 --log=stdout &
NGROK_PID=$!
sleep 3

# Récupérer l'URL publique ngrok
NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['tunnels'][0]['public_url'])" 2>/dev/null)
echo ""
echo "✅ Backend accessible publiquement sur : $NGROK_URL"
echo "   → Mets cette URL dans l'app : $NGROK_URL/api/metrics"
echo ""
echo "Appuie sur Ctrl+C pour tout arrêter"
wait $SERVER_PID

@echo off
setlocal

set DISABLE_TLS=true
set ENVIRONMENT=development
set LOG_LEVEL=info
set JWT_SECRET=easychat-jwt-signing-secret-key-2026
set DATABASE_URL=postgres://nearby_user:nearby_secure_pass@127.0.0.1:54322/nearby_connect?sslmode=disable
set REDIS_URL=127.0.0.1:6379
set REDIS_ADDR=127.0.0.1:6379
set KAFKA_BROKERS=127.0.0.1:9092
set AUTH_HOSTS=http://127.0.0.1:8081
set USER_HOSTS=http://127.0.0.1:8085
set CHAT_HOSTS=http://127.0.0.1:8082
set NEARBY_HOSTS=http://127.0.0.1:8088
set PRES_HOSTS=http://127.0.0.1:8084
set MEDIA_HOSTS=http://127.0.0.1:8086
set COMPLIANCE_HOSTS=http://127.0.0.1:8087

if not exist logs mkdir logs
if not exist bin echo ERROR: bin\ directory missing. Run build first. & exit /b 1

echo [1/8] Auth (8081)
set PORT=8081
start "auth" /b bin\auth.exe >> logs\auth.log 2>> logs\auth.err

echo [2/8] User (8085)
set PORT=8085
start "user" /b bin\user.exe >> logs\user.log 2>> logs\user.err

echo [3/8] Chat (8082)
set PORT=8082
start "chat" /b bin\chat.exe >> logs\chat.log 2>> logs\chat.err

echo [4/8] Nearby (gRPC: 8083, HTTP: 8088)
set PORT=8083
start "nearby" /b bin\nearby.exe >> logs\nearby.log 2>> logs\nearby.err

echo [5/8] Presence (8084)
set PORT=8084
start "presence" /b bin\presence.exe >> logs\presence.log 2>> logs\presence.err

echo [6/8] Notification (8087)
set PORT=8087
start "notification" /b bin\notification.exe >> logs\notification.log 2>> logs\notification.err

echo [7/8] Media (8086)
set PORT=8086
start "media" /b bin\media.exe >> logs\media.log 2>> logs\media.err

echo Waiting 5s for microservices...
ping 127.0.0.1 -n 6 > nul

echo [8/8] Gateway (8090)
set PORT=8090
start "gateway" /b bin\gateway.exe >> logs\gateway.log 2>> logs\gateway.err

echo Waiting 3s for gateway...
ping 127.0.0.1 -n 4 > nul

echo.
echo === Health Checks ===
curl -s -w " HTTP:%%{http_code}" http://127.0.0.1:8090/healthz
echo   gateway:8090
curl -s -w " HTTP:%%{http_code}" http://127.0.0.1:8081/healthz
echo   auth:8081
curl -s -w " HTTP:%%{http_code}" http://127.0.0.1:8085/healthz
echo   user:8085
curl -s -w " HTTP:%%{http_code}" http://127.0.0.1:8082/healthz
echo   chat:8082

echo.
echo === ADB ===
adb -s 10MG5XFK9A0006B reverse tcp:18080 tcp:8090 2>nul
echo   Device-1: 18080->8090
adb -s c541beff reverse tcp:18080 tcp:8090 2>nul
echo   Device-2: 18080->8090

echo.
echo === Processes ===
tasklist /FI "IMAGENAME eq gateway.exe"
tasklist /FI "IMAGENAME eq auth.exe"

echo.
echo Done. Logs: %CD%\logs\
echo Stop: taskkill /IM gateway.exe /F ^& taskkill /IM auth.exe /F ^& taskkill /IM nearby.exe /F

endlocal

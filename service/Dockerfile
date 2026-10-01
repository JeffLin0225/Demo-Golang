# ---------- Build Stage ----------
FROM golang:1.25.5-alpine3.21 AS builder

WORKDIR /app

# Service 有引入 gin / godotenv，go.sum 必須一起複製，否則 go mod download 會失敗
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# 只編譯 Service 這個 package，不指定路徑會編到根目錄的 web server
#
# 輸出路徑刻意放在 /out/ 而不是 /app/service：如果輸出檔名跟來源目錄同名
# （-o service ./service），go build 遇到 /app/service 已經是個目錄，
# 就會把 binary 放進那個目錄裡變成 /app/service/service，而不是取代它。
# 下面 COPY --from=builder 會變成複製整個原始碼目錄（含 .env、main.go...），
# 不是單一個 binary 檔案——之前就是這樣把本機 .env 的設定意外打進最終 image。
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/service ./service

# ---------- Runtime Stage ----------
FROM alpine:3.21

RUN apk add --no-cache ca-certificates tzdata \
    && addgroup -S app && adduser -S app -G app

WORKDIR /app
# 只拷貝編譯好的單一 binary，不會帶到任何原始碼或 .env
COPY --from=builder /out/service ./service

USER app

# 常駐 HTTP 服務，對應 main.go 的 r.Run(":8080")
EXPOSE 8080

ENTRYPOINT ["./service"]

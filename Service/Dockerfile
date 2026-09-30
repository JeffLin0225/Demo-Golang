# ---------- Build Stage ----------
FROM golang:1.25.5-alpine3.21 AS builder

WORKDIR /app

# Service 有引入 gin / godotenv，go.sum 必須一起複製，否則 go mod download 會失敗
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# 只編譯 Service 這個 package，不指定路徑會編到根目錄的 web server
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o service ./Service

# ---------- Runtime Stage ----------
FROM alpine:3.21

RUN apk add --no-cache ca-certificates tzdata \
    && addgroup -S app && adduser -S app -G app

WORKDIR /app
COPY --from=builder /app/service .

USER app

# 常駐 HTTP 服務，對應 main.go 的 r.Run(":8080")
EXPOSE 8080

ENTRYPOINT ["./service"]

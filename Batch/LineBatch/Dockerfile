# ---------- Build Stage ----------
FROM golang:1.25.5-alpine3.21 AS builder

WORKDIR /app

# go.mod 在 Demo-Golang 根目錄，建置 context 需設為該目錄
COPY go.mod ./
RUN go mod download

COPY . .

# 只編譯 LineBatch 這個 package
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o linebatch ./Batch/LineBatch

# ---------- Runtime Stage ----------
FROM alpine:3.21

RUN apk add --no-cache ca-certificates tzdata \
    && addgroup -S app && adduser -S app -G app

WORKDIR /app
COPY --from=builder /app/linebatch .

USER app

# 批次任務跑完即結束，不需要 EXPOSE / HEALTHCHECK
ENTRYPOINT ["./linebatch"]

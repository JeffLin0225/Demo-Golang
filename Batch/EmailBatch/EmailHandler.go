package main

import (
	"log"
	"time"
)

func main() {

	log.Printf("開始進行 Email 批次@")

	time.Sleep(5 * time.Second)

	log.Printf(" Email 資料發送中...")

	time.Sleep(5 * time.Second)

	log.Printf("Email 發送完畢！")

}

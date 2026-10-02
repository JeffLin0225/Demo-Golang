package main

import (
	"log"
	"time"
)

func main() {

	log.Printf("開始進行 Line 批次@")

	time.Sleep(2 * time.Second)

	log.Printf(" Line 資料發送中...")
	log.Printf(" 確認有用新版")

	time.Sleep(3 * time.Second)

	log.Printf("Line 發送完畢！")

}

package main

import (
	"fmt"
	"github.com/zeebo/xxh3"
	"time"
)

func work(input []byte, rounds int) uint64 {
	var checksum uint64
	for i := 0; i < rounds; i++ {
		checksum ^= xxh3.HashSeed(input, uint64(i))
	}
	return checksum
}

var warm uint64

func main() {
	input := make([]byte, 1024)
	for i := range input {
		input[i] = byte(i * 17)
	}
	warm = work(input, 10)
	start := time.Now()
	checksum := work(input, 1000)
	elapsed := time.Since(start).Nanoseconds()
	fmt.Println(int64(checksum), elapsed)
}

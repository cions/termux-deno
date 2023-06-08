package main

import (
	"fmt"
	"net"
	"os"
)

func main() {
	fmt.Printf("127.0.0.1\tlocalhost\n")
	fmt.Printf("::1\tip6-localhost\n")
	fmt.Printf("\n")

	for _, host := range os.Args[1:] {
		addrs, err := net.LookupIP(host)
		if err != nil {
			panic(err)
		}
		for _, addr := range addrs {
			if ip4 := addr.To4(); ip4 != nil {
				fmt.Printf("%v\t%s\n", ip4, host)
				break
			}
		}
	}
}

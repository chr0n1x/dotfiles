package main

import (
	"fmt"
	"os"

	"github.com/enetx/surf"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: surf-cli <url>")
		os.Exit(1)
	}

	client := surf.NewClient().Builder().Impersonate().Chrome().Build()
	if client.Err() != nil {
		fmt.Fprintf(os.Stderr, "error building client: %v\n", client.Err())
		os.Exit(1)
	}

	resp := client.Get(os.Args[1]).Do()
	if resp.Err() != nil {
		fmt.Fprintf(os.Stderr, "error fetching %s: %v\n", os.Args[1], resp.Err())
		os.Exit(1)
	}

	body, err := resp.Body.String().Result()
	if err != nil {
		fmt.Fprintf(os.Stderr, "error reading body: %v\n", err)
		os.Exit(1)
	}

	fmt.Fprint(os.Stdout, body)
}

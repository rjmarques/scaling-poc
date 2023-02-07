package main

import (
	"fmt"
	"net/http"

	"github.com/gorilla/mux"
)

func main() {
	r := mux.NewRouter()
	r.HandleFunc("/health", func(http.ResponseWriter, *http.Request) {
		fmt.Println("got health check Request")
	})
	panic(http.ListenAndServe(":8080", r))
}

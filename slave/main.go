package main

import (
	"fmt"
	"math"
	"net/http"
	"sync"
	"sync/atomic"

	"github.com/gorilla/mux"
)

var activeStreesMode atomic.Bool
var staticVersion = "V1.0.0"

func main() {
	fmt.Println("Running version:", staticVersion)

	wakeChan := make(chan bool)

	go cpuStressMode(wakeChan)

	r := mux.NewRouter()
	r.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		fmt.Println("got health check Request")
		w.Write([]byte("healthy as an ox"))
	})
	r.HandleFunc("/burn", func(w http.ResponseWriter, r *http.Request) {
		fmt.Println("got cpu burn Request")
		if activeStreesMode.CompareAndSwap(false, true) {
			wakeChan <- true
		}
		w.Write([]byte("...baby burn, disk inferno!"))
	})
	r.HandleFunc("/chill", func(w http.ResponseWriter, r *http.Request) {
		fmt.Println("got cpu burn stop Request")
		activeStreesMode.CompareAndSwap(true, false)
		w.Write([]byte("no more burning"))
	})
	panic(http.ListenAndServe(":8080", r))
}

func cpuStressMode(wake chan bool) {
	// super simple multi threaded busy work with a simple interrupt
	for range wake {
		var wg sync.WaitGroup
		wg.Add(2) // the instances have 2 CPUs

		for i := 0; i < 2; i++ {
			go func() {
				defer wg.Done()

				for {
					if activeStreesMode.Load() {
						count := 0.0
						for i := 0; i < math.MaxInt32; i++ {
							count++
						}
					} else {
						break
					}
				}
			}()
		}

		wg.Wait()
	}
}

all: explore

go.sum:
	go mod tidy

explore: explore.go go.sum
	go build $@

test: explore
	@echo test does nothing, try sudotest

sudotest: explore
	sudo ./explore --kill=false --errno=0
	sudo ./explore --psx --kill=false --errno=0
	sudo ./explore --kill=false ; if [[ $$? -ne 0 ]]; then echo expected error observed ; exit 0 ; fi ; echo should have failed ; exit 1
	sudo ./explore --psx --kill=false ; if [[ $$? -ne 0 ]]; then echo expected error observed ; exit 0 ; fi ; echo should have failed ; exit 1

clean:
	rm -f explore go.sum *~

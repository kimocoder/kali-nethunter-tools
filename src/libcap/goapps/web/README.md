# Web serving with/without privilege

## Building

This sample program works with go1.16+:
```
   go mod tidy
   go build web.go
```

## Further discussion

A more complete walk through of what this code does is provided on the
[Fully Capable
website](https://sites.google.com/site/fullycapable/getting-started-with-go/building-go-programs-that-manipulate-capabilities).

## Reporting bugs

Go compilers prior to go1.16 are not expected to work. Report more
recent issues to the [`libcap` bug
tracker](https://bugzilla.kernel.org/buglist.cgi?component=libcap&list_id=1065141&product=Tools&resolution=---).

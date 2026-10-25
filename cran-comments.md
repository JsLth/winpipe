## R CMD check results

0 errors | 0 warnings | 2 notes

* This is a new release.

* There is one instance of \dontrun{}, which wraps a POST request that changes the docker state and is hard to clean up. Users are advised to run the code only if they are aware that this will change the state of an external program (docker).

* checking compiled code ... NOTE

```
File 'winpipe/libs/x64/winpipe.dll':
  Found non-API calls to R: 'R_GetConnection',
    'R_new_custom_connection'
```

The purpose of the package is to expose Windows named pipes as standard R connections, so that they work with `readLines()`, `writeLines()`, `readBin()`, `writeBin()`, and other non-blocking reads. The only way to do this is `R_new_custom_connection` together with `R_GetConnection`. These are the only two non-API entry points used.

To limit the risk from the experimental interface, the package:

* includes only the public header and fails to compile if `R_CONNECTIONS_VERSION != 1`
* verifies the connection class before using the retrieved struct
* is restricted to Windows (`OS_type: windows`)

I am happy to adapt the package if R-core provides an API-compliant alternative, or to take any other action CRAN prefers.

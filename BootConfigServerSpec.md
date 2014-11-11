# Boot Configuration Server Spec

The WebBootCore agent is a TinyCore based OS that is loaded, with the job of bootstrapping the environment for the real system image. It allows for more flexible and scriptable selection of the boot image, and uses `kexec` to boot the new kernel. The system image, kernel and initramfs can be retrieved over HTTP from any standard web server. 

The Boot Configuration Server is responsible for holding information to identify a client and what OS image it should start with.

<img src="BootToTheWeb process.png" />

## The Server

* You can use any standard HTTP server.
* It must serve files from the root of the directory structure.
* A default configuration file simply named `default` must exist on the server (i.e. http://yourserver/default)

### Configuration

A typical configuration file is very similar to the `pxelinux.cfg` format, except that the initrd is split out from the append line, and you specify a server to retrieve the kernel and initrd assets from.

```
SERVER yourserver
KERNEL vmlinuz
INITRD core.gz
APPEND ro nomodeset boot=boottotheweb server=yourserver filename=image.squash
```

The specified paths for `KERNEL` and `INITRD` will be looked up using HTTP on `SERVER`, i.e. for the example above, the kernel will be retrieved as:

`http://yourserver/vmlinuz`

### Per Client Configuration

Create a configuration file as above, named with the human readable MAC address format, separated with colons and in lowercase. For example, `01:23:45:67:89:ab`. The client will request this file automatically before requesting the default configuration.
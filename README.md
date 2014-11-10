# BootToTheWeb

BootToTheWeb allows you to boot Linux from the network or the internet.

The filesystem is squashed on the server into a SquashFS image and transferred over HTTP to the client. The client downloads the image on startup and stores it in RAM, which is then used as the boot drive.


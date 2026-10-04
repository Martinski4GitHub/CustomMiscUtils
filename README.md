# CustomMiscUtils
A collection of custom shell scripts that can be used for specific tasks.

## Custom Email Library Script
## v1.1.0
### Updated on 2026-Oct-04

The shared Custom Email Library script can be used on ASUS routers running **Asuswrt-Merlin** firmware:

```bash
/jffs/addons/shared-libs/CustomEMailFunctions.lib.sh
```

## License

The **CustomEMailFunctions.lib.sh** script is free and open-source software licensed under the
[GNU General Public License version 3.0](LICENSE).

Official CustomEMailFunctions.lib.sh releases are maintained through this repository:

** https://github.com/Martinski4GitHub/CustomMiscUtils/tree/master/EMail **

### Project Author

- **Original Author & Creator:**  @Martinski W.

## Installation

**Manual Installation**

1. To download the script to your router, use the following commands:

```bash
curl  -LSs --retry 3 --retry-delay 5 --retry-connrefused \
https://raw.githubusercontent.com/Martinski4GitHub/CustomMiscUtils/master/EMail/CustomEMailFunctions.lib.sh
-o /jffs/addons/shared-libs/CustomEMailFunctions.lib.sh && chmod a+x /jffs/addons/shared-libs/CustomEMailFunctions.lib.sh
```

The shared Custom Email Library script is not a standalone script; it's a library meant to be "sourced" (i.e included) within a script so that its functionality can be accessed via the available function calls.


# Hardware support

Support has two layers:

1. the kernel must expose `pwm1` through `hp_wmi`;
2. the daemon must be tested against the machine's temperature and fan layout.

Check the board ID with:

```sh
cat /sys/class/dmi/id/board_name
```

## Verified

| board | product | kernel | fans | reporter |
|---|---|---|---:|---|
| `8C99` | Victus by HP Gaming Laptop 16-r1xxx | 7.1.3 | 2 | maintainer |

## Kernel allowlist

These boards are present in the relevant `hp_wmi` driver work but have not all
been verified with hpfand.

| family | boards |
|---|---|
| Victus | `8BBE`, `8BD4`, `8BD5`, `8C99`, `8C9C`, `8D41` |
| Omen | `8BAB`, `8BCA`, `8BCD`, `8C76`, `8C78`, `8A4D` |

An allowlisted board is not a guarantee. Firmware revisions and sensor layouts
can differ between products sharing a family name.

Submit a [hardware compatibility report](https://github.com/emomaxd/hpfand/issues/new?template=hardware.yml)
to add a tested machine. Do not include serial numbers or UUIDs.

# Create an access control entry

Builds a single ACE for use with
[`sd_add()`](https://jslth.github.io/winpipe/reference/security_descriptor.md).
Types, flags, rights and well-known accounts can be given either as
their SDDL abbreviation (e.g. `"GA"`) or by description (e.g.
`"generic all"`). See details for lookup tables.

## Usage

``` r
ace(
  type = "allow",
  flags = NULL,
  rights = NULL,
  object_guid = NULL,
  inherit = NULL,
  account = NULL
)
```

## Arguments

- type:

  `[character(1)]`

  ACE type. Defaults to `"allow"`.

- flags:

  `[character]`

  ACE flags, e.g. `c("CI", "OI")`.

- rights:

  `[character]`

  Access rights, e.g. `c("GR", "GW")`.

- object_guid, inherit:

  `[character(1)]`

  Optional object GUIDs for object-specific ACE types.

- account:

  `[character(1)]`

  An alias, description or SID of a trusted account.

## Value

A list of class `"winpipe_ace"`.

## Details

The following codes and descriptions can be used interchangeably for ACE
components:

**`type`:**

|          |                              |
|----------|------------------------------|
| **Code** | **Description**              |
| A        | allow                        |
| D        | deny                         |
| OA       | object-specific access allow |
| OD       | object-specific access deny  |
| AU       | system audit                 |
| AL       | system alarm                 |
| OU       | object-specific system audit |
| ML       | mandatory label              |

**`flags`:**

|          |                         |
|----------|-------------------------|
| **Code** | **Description**         |
| OI       | object inherit          |
| CI       | container inherit       |
| NP       | no propagate inherit    |
| IO       | inherit only            |
| ID       | inherited ACE           |
| SA       | successful access audit |
| FA       | failed access audit     |

**`rights`:**

|          |                      |
|----------|----------------------|
| **Code** | **Description**      |
| GA       | generic all          |
| GR       | generic read         |
| GW       | generic write        |
| GX       | generic execute      |
| FA       | file all access      |
| FR       | file generic read    |
| FW       | file generic write   |
| FX       | file generic execute |
| KA       | key all access       |
| KR       | key read             |
| KW       | key write            |
| KX       | key execute          |
| RP       | read property        |
| WP       | write property       |
| WD       | modify permissions   |
| RC       | read control         |
| SD       | delete               |
| WO       | change owner         |
| NW       | no write up          |
| NR       | no read up           |
| NX       | no execute up        |

**`account`:**

|          |                          |
|----------|--------------------------|
| **Code** | **Description**          |
| BA       | admins                   |
| WD       | everyone                 |
| SY       | local system             |
| AU       | authenticated users      |
| LS       | local service            |
| NS       | network service          |
| AN       | anonymous                |
| IU       | interactive users        |
| CO       | creator owner            |
| CG       | creator group            |
| AC       | all application packages |
| LW       | low integrity            |
| ME       | medium integrity         |
| HI       | high integrity           |
| SI       | system integrity         |

## Examples

``` r
# codes are allowed
ace("A", rights = "GA", account = "SY")
#> <winpipe_ace> (A;;GA;;;SY)

# as well as generic descriptions
ace("allow", rights = "generic all", account = "local system")
#> <winpipe_ace> (A;;GA;;;SY)
```

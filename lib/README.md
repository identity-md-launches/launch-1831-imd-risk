# Vendored dependencies

Sources are copied unchanged from the following official releases. Everything
needed by the build is committed as ordinary files; no Git submodules, package
manager, or network lookup is required during verification.

| Dependency | Version | Commit | Included files |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/c64a1edb67b6e3f4a15cca8909c9482ad33a02b0) | `v5.4.0` | `c64a1edb67b6e3f4a15cca8909c9482ad33a02b0` | ERC20 and its four transitive Solidity imports; MIT license |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/77041d2ce690e692d6e03cc812b57d1ddaa4d505) | `v1.9.7` | `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | Entire `src/` tree; Apache-2.0 and MIT licenses |

[`dependencies.json`](dependencies.json) records the upstream URLs, release tags,
resolved commits, downloaded archive SHA-256 digests, and SHA-256 digests for each
vendored file. OpenZeppelin supplies the production ERC-20 implementation;
forge-std is used only by tests. The remappings are in the repository root.


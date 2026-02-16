# Swift Dependency Submission

This GitHub Action calculates dependencies for a Swift package and submits the list to the [Dependency submission API](https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/using-the-dependency-submission-api). Dependencies then appear in your repository's dependency graph, and you'll receive Dependabot alerts and updates for vulnerable or out-of-date dependencies.

### Example
```yaml
name: Swift Dependency Submission
on:
  push:
    branches:
      - main

# The API requires write permission on the repository to submit dependencies
permissions:
  contents: write

jobs:
  swift-action-detection:
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout Repository'
        uses: actions/checkout@v6

      - uses: vapor/swiftly-action@v0.2
        with:
          toolchain: latest

      - name: Run snapshot action
        uses: actions/swift-dependency-submission@v0.2
```

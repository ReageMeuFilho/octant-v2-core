# Base Strategy

## Smart Contract Overview:

This is an abstract contract that should be inherited by a specific strategy. It implements all of the required functionality toseamlessly integrate with the `TokenizedStrategy` implementation contract allowing anyone to easily build a fully permissionless ERC-4626 compliant Vault by inheriting this contract and overriding four simple functions.

It utilizes an immutable proxy pattern that allows the BaseStrategy to remain simple and small. All standard logic is held within the
`TokenizedStrategy` and is reused over any n strategies all using the `fallback` function to delegatecall the implementation so that strategists can only be concerned with writing their strategy specific code.

This contract should be inherited and the four main abstract methods `_deployFunds`, `_freeFunds`, `_harvestAndReport` and `liquidatePosition` implemented to adapt the Strategy to the particular needs it has to generate yield. There are
other optional methods that can be implemented to further customize
the strategy if desired.

All default storage for the strategy is controlled and updated by the
`TokenizedStrategy`. The implementation holds a storage struct that
contains all needed global variables in a manual storage slot. This
means strategists can feel free to implement their own custom storage
variables as they need with no concern of collisions. All global variables
can be viewed within the Strategy by a simple call using the
`TokenizedStrategy` variable. IE: TokenizedStrategy.globalVariable();.

## Smart Contract Flow Diagram:

![Base Strategy Flow Diagram](https://private-user-images.githubusercontent.com/31198893/375276372-ed85b836-92c5-4054-8cc2-064ce1d47f97.svg?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3Mjg1NDY5NDAsIm5iZiI6MTcyODU0NjY0MCwicGF0aCI6Ii8zMTE5ODg5My8zNzUyNzYzNzItZWQ4NWI4MzYtOTJjNS00MDU0LThjYzItMDY0Y2UxZDQ3Zjk3LnN2Zz9YLUFtei1BbGdvcml0aG09QVdTNC1ITUFDLVNIQTI1NiZYLUFtei1DcmVkZW50aWFsPUFLSUFWQ09EWUxTQTUzUFFLNFpBJTJGMjAyNDEwMTAlMkZ1cy1lYXN0LTElMkZzMyUyRmF3czRfcmVxdWVzdCZYLUFtei1EYXRlPTIwMjQxMDEwVDA3NTA0MFomWC1BbXotRXhwaXJlcz0zMDAmWC1BbXotU2lnbmF0dXJlPWYyOWRiZmFiMDg3NDMyZTAwMDc1OGYwOThmNzg3ODViNTU5NGE2NGY3OTM4ZDFkMDYyN2VlOTAxNTdiM2UxNmImWC1BbXotU2lnbmVkSGVhZGVycz1ob3N0In0.EbimkFEIdZY98KlpEiGtesdUjw2vj9EJbNxgo4XSzec)

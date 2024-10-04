# Octant Rewards Safe Module

## Smart Contract Overview:

Octant Rewards Safe Module is a custom module built for managing golem foundation's staking operations to fund Octant which currently has setup limitations.

- Owner request's adding and removing of validators which is fulfilled by the keeper (node operator).
- Keeper confirms addition of new validators and removal of validators. When removal of validators is confirmed, principal from safe multisig is moved to the treasury address.
- harvest() function can be called by anyone to redirect only the yield portion to the dragon router.

## Inheritance Structure:

Detailed list of inherited contracts and their roles.

- `zodiac/core/Module.sol` - base contract that enables Safe Module functionality by forwarding calls to safe's `execTransactionFromModule`.

## Smart Contract Flow Diagram:

![Octant Rewards Safe Module Flow Diagram](https://private-user-images.githubusercontent.com/31198893/372372200-bf8347e8-4218-4b22-8762-3165499b2155.svg?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3Mjc3NzAwNDEsIm5iZiI6MTcyNzc2OTc0MSwicGF0aCI6Ii8zMTE5ODg5My8zNzIzNzIyMDAtYmY4MzQ3ZTgtNDIxOC00YjIyLTg3NjItMzE2NTQ5OWIyMTU1LnN2Zz9YLUFtei1BbGdvcml0aG09QVdTNC1ITUFDLVNIQTI1NiZYLUFtei1DcmVkZW50aWFsPUFLSUFWQ09EWUxTQTUzUFFLNFpBJTJGMjAyNDEwMDElMkZ1cy1lYXN0LTElMkZzMyUyRmF3czRfcmVxdWVzdCZYLUFtei1EYXRlPTIwMjQxMDAxVDA4MDIyMVomWC1BbXotRXhwaXJlcz0zMDAmWC1BbXotU2lnbmF0dXJlPTRlMjZjNTdkOWY5MGI2ODAwNjUwMDM1ZjY2Yzk2MTgwMjg0MGIxYjE5ZjI0MDU1YzdmMWFkMjViZTMwNGFlNWUmWC1BbXotU2lnbmVkSGVhZGVycz1ob3N0In0.hcJLKj_l9Pjx44A0Nw0BrbMt6owjhvqxSBRN97YDdOY)

## Attack Surface:

- AS1: havest() would be bricked if yield is kept accumulating for a long time which results in owner().balance exceeding maxYield. In that case the owner of the module would have to manually send the yield to the dragon router.
- AS2: If the owner's safe multisig is exploited (ie. private keys are leaked) then attacker can increase the max yield and redirect the principal to the dragon router. In this case also the funds would not be lost. We will have rescue funds on the dragon router which may allow us to rescue these funds.

## Mitigation Strategies:

- AS1: To migitate this we setup a bot that harvest at regular intervals to avoid owner().balance exceeding maxYield.
- AS2: We could add Octant Governance multisig as a second to the dragon's safe which would re-verify transactions and provide another layer of security.

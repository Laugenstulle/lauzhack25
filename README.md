# Buying Ticket
## User sends request for Ticket
### User provided ticket information
- Train station from and to
- valid time from and to
- ticket type
- *validating method* (Anonymous SBB card, personal ID)
- *user hash* (combination hash of id from validating method + random chosen number)

### Explanation
The *validating method* has no technical relevance. It is only to know which medium is to use for validating.
The *user hash* is a combination of the number found in your validating method with a random number. The random number is because you could otherwise use a rainbow table to get the number from your validating method.

## Server answers with Ticket
note: The response is signed with a public key from SBB to validate it´s authenticity.
### Information in Ticket
- Train station from and to
- valid time from and to
- ticket type
- price
- *validating method* (same as user send)
- *random ticket number* (random number in which the user has no influence in choosing)
- *ticket hash* (combination hash of *user hash*  + *random ticket number*)
### after receiving the ticket
The computer generates a pdf with all with the relevant Ticket information visible and a QR code containing the signed Ticket information and the random number chosen by the user, which is later used for validating.
# Validating Ticket
If you are on a train and SSB employ want´s to check your ticket, the following happens.

## Step 1 SBB Employe
- Employee scans ticket 
- it checks if the ticket is valid at the current time
- it checks if the ticket is valid at the current location
- it sends the random ticket number from the scanned ticket (which contains no information about the owner) to the server together which his location
## Step 2 SBB Server
- if the random ticket number is seen for the first time, add it to database (gets deleted each day)
- if it already present in the database we do check if the last check is old ennough and the new location logical.
- if yes send to the SBB employee that all is fine.
- if not send that he needs to do a additional check

## Step 3 SBB Employee
- if server says it´s fine he moves on
- if additional check is required person traveling needs to provide his method of validation with which the employee can scan it to recreate to hash found on the signed ticket
- if recreatable the employee wishes a nice day and moves on
- if not recreatable the person travailing is not the rightful owner of the ticket

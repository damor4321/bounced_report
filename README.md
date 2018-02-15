BOUNCED REPORT
==============

This is a very useful perl script that condenses a lot of knowledge and experience with the SMTP protocol.

The script permits us to generate a report on the failure cases (bounces) in delivering mail in a mass mailing campaign. 

This analysis is essential to diagnose existing problems with our recipients (filters too strict, misconfigured servers, blacklists, sender reputation, etc.) and propose strategic corrections in mass mailing campaigns.

A basic practice in massive mailing is set a return-path: a mailbox to which all the bounced mails of the campaign will arrive. This script connects via IMAP protocol to this mailbox and analyzes the messages in it (failure reports according to the SMTP protocol)

From the classification of codes and error messages the script generates a human-readable csv file.

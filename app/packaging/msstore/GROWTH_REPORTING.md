# Read-only acquisition reporting

`read_growth.py` collects existing Microsoft Store and Snap reports. It performs
no listing, release, account, consent, billing or report-generation writes.
The only POST is the existing certificate-authenticated OAuth token exchange.

Run the registered `msstore-readonly-evidence.yml` workflow on the reviewed branch,
supplying a recipient RSA public key of at least 3072 bits. Private keys and
decryption stay with the requester. Provider credentials remain in the existing
protected environment; the only artifact is authenticated, recipient-encrypted
JSON. No raw provider errors or tokens are printed. The workflow uses the standard
`ubuntu-24.04` runner, with its existing production concurrency group.

The default window ends yesterday UTC and starts at most 89 days before today.
Dates in the provider responses retain their native semantics; the UTC cutoff
does not establish Microsoft's reporting timezone. Missing dates remain unknown.
Month-to-date and preceding-month usage are queried separately. A Windows429
defers remaining Windows calls and records Retry-After; Snap remains independent.
No automatic credential renewal, new grant or paid fallback is attempted.

Two GET-only legacy funnel reads retain the original Windows experiment windows
while inside the supported date range. Their population is distinct from the
installation-event endpoint. The reader does not join those populations or
calculate conversion/lift. An empty or missing funnel step is not a measured zero.
Historical windows outside the supported range are marked unavailable.

Snap metrics are store check-ins, not app launches or MAU. Counts remain null
where the provider returns null. Date ranges, series lengths, nonnegative integer
counts and provider status are validated before accepting a metric.

Run offline boundary tests before dispatch:

```sh
python3 -m unittest discover -s app/packaging/msstore -p 'test_read_*.py'
```

Check the exact remote head before dispatch and verify the accepted run head,
artifact digest and authenticated decryption afterward. A successful workflow
can contain a failed source observation; consumers must inspect each source,
retain last-good evidence and expose the failed refresh separately. Dispatching
this reader does not authorize a release or submission workflow.

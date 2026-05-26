# Common Errors

Slack documents the same set of errors on nearly every Web API method page —
authentication failures, rate limiting, deprecated endpoints, transport
problems, and so on. To keep per-method docs focused, those shared errors
are listed here once and stripped from each method's own error list.
Method-specific errors (e.g. `channel_not_found`, `is_archived`) remain on
the method itself.

## Errors

* `access_denied` — Access to a resource specified in the request is denied.
* `accesslimited` — Access to this method is limited on the current network
* `account_inactive` — Authentication token is for a deleted user or workspace when using a `bot` token.
* `deprecated_endpoint` — The endpoint has been deprecated.
* `ekm_access_denied` — Administrators have suspended the ability to post a message.
* `enterprise_is_restricted` — The method cannot be called from an Enterprise.
* `fatal_error` — The server could not complete your operation(s) without encountering a catastrophic error. It's possible some aspect of the operation succeeded before the error was raised.
* `internal_error` — The server could not complete your operation(s) without encountering an error, likely due to a transient issue on our end. It's possible some aspect of the operation succeeded before the error was raised.
* `invalid_arg_name` — The method was passed an argument whose name falls outside the bounds of accepted or expected values. This includes very long names and names with non-alphanumeric characters other than `_`. If you get this error, it is typically an indication that you have made a _very_ malformed API call.
* `invalid_arguments` — The method was called with invalid arguments.
* `invalid_array_arg` — The method was passed an array as an argument. Please only input valid strings.
* `invalid_auth` — Some aspect of authentication cannot be validated. Either the provided token is invalid or the request originates from an IP address disallowed from making the request.
* `invalid_charset` — The method was called via a `POST` request, but the `charset` specified in the `Content-Type` header was invalid. Valid charset names are: `utf-8` `iso-8859-1`.
* `invalid_form_data` — The method was called via a `POST` request with `Content-Type` `application/x-www-form-urlencoded` or `multipart/form-data`, but the form data was either missing or syntactically invalid.
* `invalid_post_type` — The method was called via a `POST` request, but the specified `Content-Type` was invalid. Valid types are: `application/json` `application/x-www-form-urlencoded` `multipart/form-data` `text/plain`.
* `method_deprecated` — The method has been deprecated.
* `missing_post_type` — The method was called via a `POST` request and included a data payload, but the request did not include a `Content-Type` header.
* `missing_scope` — The token used is not granted the specific scope permissions required to complete this request.
* `no_permission` — The workspace token used in this request does not have the permissions necessary to complete the request. Make sure your app is a member of the conversation it's attempting to post a message to.
* `not_allowed_token_type` — The token type used in this request is not allowed.
* `not_authed` — No authentication token provided.
* `org_login_required` — The workspace is undergoing an enterprise migration and will not be available until migration is complete.
* `ratelimited` — The request has been ratelimited. Refer to the `Retry-After` header for when to retry the request.
* `request_timeout` — The method was called via a `POST` request, but the `POST` data was either missing or truncated.
* `service_unavailable` — The service is temporarily unavailable
* `team_access_not_granted` — The token used is not granted the specific workspace access required to complete this request.
* `team_added_to_org` — The workspace associated with your request is currently undergoing migration to an Enterprise Organization. Web API and other platform operations will be intermittently unavailable until the transition is complete.
* `token_expired` — Authentication token has expired
* `token_revoked` — Authentication token is for a deleted user or workspace or the app has been removed when using a `user` token.
* `two_factor_setup_required` — Two factor setup is required.

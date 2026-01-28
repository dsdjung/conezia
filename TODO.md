I don't see UI for connecting to various online services. Update documents, implementation and validation to create a framework for intent based external service integration and token management. First use of integration is to populate my relationships

Define unique data points such as email, SSN, phone number.
When such unique data is added, either for a connection or for a registered user, there should be connection alert to everybody with that unique data point.

Feature completeness and correctness
Test completeness and correctness
e2e testing


Import Adapters Not Implemented: The design mentions adapters for Google Contacts, CSV, vCard in lib/conezia/imports/adapters/ but these appear to be planned (part of the integration framework plan)

Some Health Features Incomplete: get_weekly_digest returns hardcoded zeros for relationships_improved and relationships_declining

What external integration makes sense


Android and iOS app with feature parity and consistent user experience.

Additional possible considerations for deduplicating
- store connection's id from the service the connection was synced from.
- display where the connection was synced from on UI.
- provide UI mechanism to select connections and combine them into a single connection
- store all the service ids from which the synced connections were merged from
- further sync should now be able to refer to the combined connection if id match

If I sync again, we need to handle a case where there is changed data for a connection from the last time it was synced.

shared experience?

Connected to field for creating event should be searchable, and select multiple connections


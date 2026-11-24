import Foundation

extension Schema {
    /// A model only proposes a home. `fact_home` read the latest `fact_link` row whatever its `how`, so a proposal
    /// became the home before a person acted. It now reads only the rows that set a home: the folder of the machine, the
    /// work object a fact was made from, and a person's confirmation or move. A proposal stays in `fact_link` as a row,
    /// and `Queries.proposedHome` reads it while it is newer than the home.
    static let homeByPerson = [
        "DROP VIEW fact_home",
        """
        CREATE VIEW fact_home AS SELECT id, item_id, object_id, how, at, surface
        FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY item_id ORDER BY at DESC, id DESC) AS rank FROM fact_link
            WHERE how IN ('machineFolder','origin','personConfirmed','personMoved'))
        WHERE rank = 1
        """,
    ]
}

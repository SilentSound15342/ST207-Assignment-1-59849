# ST207 Assignment 1 (AT2026) - E-commerce database

Candidate number: 59849

| Question | Deliverable | File |
|---|---|---|
| Report | PDF report | `ST207_Assignment1_Report_59849_FINAL.pdf` |
| Q1 | E-R model: image and ERDPlus source file | `models/ER_Model_FINAL.png`, `models/ER_Model_FINAL.erdplus` |
| Q2 | Relational model: image and ERDPlus source file | `models/Relational_Model_FINAL.png`, `models/Relational_Model_FINAL.erdplus` |
| Q3 | Database creation (tables, keys, indexes, views) | `sql/Q3_Ecommerce_Schema_FINAL.sql` |
| Q4 | Synthetic data generator | `data/Synthetic_Data_Generator_FINAL.py` |
| AI | Chat log of the report proofreading and review conversation with Claude | `data/Claude_Chat_Log_Report_Review_FINAL.pdf` |
| Q4 | Generated data | `sql/Q4_Ecommerce_Data_FINAL.sql` |
| Q4 | Data validation queries | `sql/Q4_Data_Validation_FINAL.sql` |
| Q5 | Three use cases, six queries (5.1 to 5.6) | `sql/Q5_Use_Case_Queries_FINAL.sql` |
| Q6 | Triggers | `sql/Q6_Triggers_FINAL.sql` |
| Q6 | Trigger tests | `sql/Q6_Trigger_Tests_FINAL.sql` |
| Q3 to Q6 | Finished database and complete SQL script of it | `database/Q3-Q6_Ecommerce_Database_FINAL.db`, `database/Q3-Q6_Ecommerce_Database_Script_FINAL.sql` |

## Rebuilding the database
Run in SQLite (DB Browser for SQLite): `sql/Q3_Ecommerce_Schema_FINAL.sql`, then `sql/Q4_Ecommerce_Data_FINAL.sql`, then `sql/Q6_Triggers_FINAL.sql`.
Alternatively load `database/Q3-Q6_Ecommerce_Database_Script_FINAL.sql` into an empty database; it contains everything.
`data/Synthetic_Data_Generator_FINAL.py` (seed 42) reproduces `sql/Q4_Ecommerce_Data_FINAL.sql` exactly.

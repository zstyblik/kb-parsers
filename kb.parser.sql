-- kb.parser.pl PgSQL layout
CREATE TABLE account_balances (
	id_balance SERIAL NOT NULL UNIQUE, 
	date_taken TIMESTAMP NOT NULL, 
	balance MONEY NOT NULL
);

CREATE TABLE account_transactions (
	id_transaction SERIAL NOT NULL UNIQUE, 
	account_from VARCHAR NOT NULL, 
	account_to VARCHAR NOT NULL, 
	ammount MONEY NOT NULL, 
	date_executed TIMESTAMP NOT NULL, 
	variable_symbol VARCHAR DEFAULT 0, 
	specific_symbol VARCHAR DEFAULT 0
	processed BIT(1) NOT NULL DEFAULT '0',
	error_code INT NOT NULL DEFAULT 0
);

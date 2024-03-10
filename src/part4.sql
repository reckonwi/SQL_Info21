------------------------------------------ 3 tables: new_one, new_next, table_last ------------------------------------------
CREATE TABLE new_one
(
    id SERIAL NOT NULL PRIMARY KEY,
    first_column VARCHAR,
    second_column VARCHAR,
    third_column VARCHAR
);

CREATE TABLE new_next
(
    id SERIAL NOT NULL PRIMARY KEY,
    first_column VARCHAR,
    second_column VARCHAR,
    third_column VARCHAR,
    fourth_column VARCHAR,
    fifth_column VARCHAR
);

CREATE TABLE table_last
(
    id SERIAL NOT NULL PRIMARY KEY,
    first_column VARCHAR,
    second_column VARCHAR,
    third_column VARCHAR
);
INSERT INTO new_one (first_column, second_column, third_column)
VALUES ('1', '2', '3'),
    ('4', '5', '6'),
    ('7', '8', '9');
INSERT INTO new_next (first_column, second_column, third_column, fourth_column, fifth_column)
VALUES ('1', '2', '3', '4', '5'),
    ('6', '7', '8', '9', '10'),
    ('11', '12', '13', '14', '15');
INSERT INTO table_last (first_column, second_column, third_column)
VALUES ('21', '22', '23'),
    ('24', '25', '26'),
    ('27', '28', '29');
---------------------------------------------scalar functions (2)----------------------------------------------
CREATE OR REPLACE FUNCTION count_rows_in_table(table_name VARCHAR) RETURNS INT
AS $$
DECLARE
    row_count INT;
BEGIN
    EXECUTE 'SELECT COUNT(*) FROM ' || table_name INTO row_count;
    RETURN row_count;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION calculate_column_sum(table_name VARCHAR, column_name VARCHAR) RETURNS INT
AS $$
DECLARE
    total_sum INT;
BEGIN
    EXECUTE 'SELECT SUM(' || column_name || ') FROM ' || table_name INTO total_sum;
    RETURN total_sum;
END;
$$ LANGUAGE plpgsql;

--------------------------------------------trigger for test --------------------------------------------------
CREATE OR REPLACE FUNCTION trigger_function_name()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM count_rows_in_table('new_one');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER call_count_rows_trigger
AFTER INSERT ON new_one
FOR EACH ROW
EXECUTE FUNCTION trigger_function_name();

----------------------------------------------------end of data -----------------------------------------------------

-- 1) delete tables with 'tableName%'

DROP PROCEDURE IF EXISTS delete_tables;
CREATE OR REPLACE PROCEDURE delete_tables(IN tableName text)
AS $procedure$
BEGIN
    FOR tableName IN 
        SELECT table_name
        FROM information_schema.tables
        WHERE table_name LIKE tableName || '%' AND table_schema = current_schema()
    LOOP
        EXECUTE 'DROP TABLE IF EXISTS ' || tableName || ' CASCADE';
    END LOOP;
END;
$procedure$
LANGUAGE plpgsql;

-- CALL delete_tables('new');

-- 2) procedure with out parametrs get and counting function(scalar)

DROP PROCEDURE IF EXISTS scalar_functions;

CREATE OR REPLACE PROCEDURE scalar_functions(OUT numFunctions INT, OUT functionInfo TEXT)
AS $procedure$
DECLARE
    Fname TEXT;
    parameters TEXT;
BEGIN
    numFunctions := 0;
    functionInfo := '';

    FOR Fname, parameters IN 
        SELECT rou.routine_name, array_to_string(array_agg(par.parameter_name), ', ') AS parameters
        FROM information_schema.parameters AS par
        JOIN information_schema.routines AS rou ON par.specific_name = rou.specific_name
        WHERE rou.specific_schema = current_schema()
        AND rou.routine_type = 'FUNCTION'
        GROUP BY rou.routine_name
    LOOP
        numFunctions := numFunctions + 1;
        functionInfo := functionInfo || Fname || '(' || parameters || '), ';
    END LOOP;
    functionInfo := LEFT(functionInfo, LENGTH(functionInfo) - 2);
END;
$procedure$
LANGUAGE plpgsql;

-- CALL scalar_functions(NULL, NULL);

-- 3) procedure delete all triggers and out num of them
DROP PROCEDURE IF EXISTS delete_triggers;
CREATE OR REPLACE PROCEDURE delete_triggers(OUT numTriggers INT)
AS $procedure$
DECLARE
    triggerName TEXT;
    tableName TEXT;
BEGIN
    numTriggers := 0;
    FOR triggerName, tableName IN 
        SELECT trigger_name, event_object_table
        FROM information_schema.triggers
        WHERE trigger_schema = current_schema()
    LOOP
        EXECUTE 'DROP TRIGGER IF EXISTS ' || triggerName || ' ON ' || tableName;
        numTriggers := numTriggers + 1;
    END LOOP;
END;
$procedure$
LANGUAGE plpgsql;

-- CALL delete_triggers(NULL);

-- 4) procedure find in procedures and functions in sql programm text and show name and obj type

DROP FUNCTION IF EXISTS find_in_proc_and_func;
CREATE OR REPLACE FUNCTION find_in_proc_and_func(findIn TEXT) 
RETURNS TEXT
AS $function$
DECLARE
    ObjInfo TEXT := '';
    Oname TEXT;
    Objtype TEXT;
BEGIN
    FOR Oname, Objtype IN
        SELECT routine_name, routine_type
        FROM information_schema.routines
        WHERE routine_schema = current_schema()
        AND routine_type IN ('FUNCTION', 'PROCEDURE')
        AND routine_definition LIKE '%'||findIn||'%'
        ORDER BY routine_name
    LOOP
        ObjInfo := ObjInfo || Oname || '(' || Objtype || '), ' ;
    END LOOP;
    ObjInfo := LEFT(ObjInfo, LENGTH(ObjInfo) - 2);
    
    RETURN ObjInfo;
END;
$function$
LANGUAGE plpgsql;

-- SELECT * FROM find_in_proc_and_func('row_count'); --one
-- SELECT * FROM find_in_proc_and_func('rows_count'); --clean
-- SELECT * FROM find_in_proc_and_func('peer'); --many




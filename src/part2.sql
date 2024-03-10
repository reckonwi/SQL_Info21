-- -----------------------------------p2p_check_add----------------------------------- --
DROP PROCEDURE IF EXISTS p2p_check_add;
CREATE OR REPLACE PROCEDURE p2p_check_add (IN nick_checked VARCHAR(50), IN nick_checker  VARCHAR(50), IN task_name VARCHAR(50), IN check_status check_status, IN check_time time WITHOUT TIME ZONE)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    num INTEGER;
    cur_id INTEGER;
BEGIN
    SELECT count(*) , MAX(check_id) INTO num, cur_id
    FROM p2p 
    INNER JOIN checks c ON p2p.check_id = c.id
    WHERE p2p.checking_peer = nick_checker
    AND c.task = task_name
    AND c.peer = nick_checked;
    
    IF (check_status = 'Start') THEN
        IF  ( num > 0) THEN  
            RAISE EXCEPTION 'Can not add the check with "Start" status/ peer is already checking the task or task is already checked';
        ELSE
            INSERT INTO checks (id, peer, task, date)
            VALUES ((SELECT COALESCE(MAX(id), 0) + 1 FROM checks), nick_checked, task_name, NOW());

            INSERT INTO p2p (id, check_id, checking_peer, state, time)
            VALUES ((SELECT COALESCE(MAX(id), 0) + 1 FROM p2p), (SELECT MAX(id) FROM checks), nick_checker, check_status, check_time);
        END IF;
    ELSE 
        INSERT INTO p2p (id, check_id, checking_peer, state, time)
        VALUES ((SELECT COALESCE(MAX(id), 0) + 1 FROM p2p), cur_id, nick_checker, check_status, check_time);
    END IF;
END;
$procedure$;

-- ----------------------------------checks----------------------------------- --
-- CALL p2p_check_add('horse', 'raven', 'task_1', 'Start', '17:49:00');
-- CALL p2p_check_add('horse', 'raven', 'task_1', 'Success', '18:03:00');
-- CALL p2p_check_add('snake', 'horse', 'task_1', 'Start', '17:37:00');
-- CALL p2p_check_add('snake', 'horse', 'task_1', 'Success', '17:00:00');
-- CALL p2p_check_add('cat', 'dog', 'task_2', 'Start', '19:37:00');
-- CALL p2p_check_add('cat', 'dog', 'task_2', 'Failure', '19:55:00');
-- DELETE FROM p2p WHERE id = (SELECT COALESCE(MAX(id), 0) FROM p2p);
-- DELETE FROM checks WHERE id = (SELECT COALESCE(MAX(id), 0) FROM checks);

-- -----------------------------------------------------verter_check_add------------------------------------- --

DROP PROCEDURE IF EXISTS verter_check_add;
CREATE OR REPLACE PROCEDURE verter_check_add (IN nick_checked VARCHAR(50),  IN task_name VARCHAR(50), IN verter_status check_status, IN check_time time WITHOUT TIME ZONE)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    cur_id INTEGER;
BEGIN
    SELECT MAX(check_id) INTO cur_id
    FROM p2p
    INNER JOIN checks AS c ON p2p.check_id = c.id
    WHERE c.peer = nick_checked
    AND c.task = task_name
    AND p2p.state = 'Success'
    AND check_time > p2p.time;
   
    IF (verter_status = 'Start') THEN
        IF (cur_id IS NULL) THEN
            RAISE EXCEPTION 'Can not add the verter check/ p2p check is failed or in process';
        ELSE
            INSERT INTO verter (id ,check_id, state, time)
            VALUES ((SELECT MAX(id) FROM verter) + 1, cur_id, verter_status, check_time);
        END IF;  
    ELSE 
        INSERT INTO verter (id,check_id, state, time)
        VALUES (((SELECT MAX(id) FROM verter) + 1),(SELECT check_id FROM verter GROUP BY check_id  HAVING count(*) % 2= 1), verter_status, check_time);  
    END IF;
END;
$procedure$;

-- ----------------------------------checks----------------------------------- --
-- DELETE FROM verter WHERE id = (SELECT COALESCE(MAX(id), 0) FROM verter); 
-- CALL verter_check_add('snake', 'task_1', 'Start', '17:37:00');
-- CALL verter_check_add('snake', 'task_1', 'Success', '17:55:00');
-- CALL verter_check_add( 'horse', 'task_1', 'Start', '18:04:00');
-- CALL verter_check_add('horse', 'task_1', 'Success', '18:55:00');
-- CALL verter_check_add('cat', 'task_2', 'Start', '20:37:00');

-- --------------------------------triger TransferredPoints --------------------------------- --
DROP FUNCTION IF EXISTS fnc_trg_update_transferred_points() CASCADE;

CREATE OR REPLACE FUNCTION fnc_trg_update_transferred_points()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if the record exists
    IF EXISTS (
        SELECT 1
        FROM p2p
        JOIN checks ON p2p.check_id = checks.id
        WHERE state = 'Start' AND NEW.check_id = checks.id
        AND EXISTS (
            SELECT 1
            FROM transferred_points
            WHERE checking_peer = p2p.checking_peer
            AND checked_peer = checks.peer
            FOR UPDATE
        )
    ) THEN
        -- If the record exists, update it.
       WITH p2p_data AS (
        SELECT checking_peer, peer as checked_peer FROM p2p
        JOIN checks ON p2p.check_id = checks.id
        WHERE state = 'Start' AND NEW.check_id = checks.id
    )
        UPDATE transferred_points
        SET points_amount = transferred_points.points_amount + 1
        FROM p2p_data
        WHERE transferred_points.checking_peer = p2p_data.checking_peer
        AND transferred_points.checked_peer = p2p_data.checked_peer;
    ELSE
        -- Otherwise, insert a new record.
        WITH new_checks AS (SELECT checking_peer, peer as checked_peer FROM p2p
        JOIN checks ON p2p.check_id = checks.id
        WHERE state = 'Start' AND NEW.check_id = checks.id)
        INSERT INTO transferred_points (id,checking_peer, checked_peer, points_amount)
        VALUES ((SELECT MAX(id) FROM transferred_points)+1,(SELECT checking_peer FROM new_checks), (SELECT checked_peer FROM new_checks), 1);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER fnc_trg_update_transferred_points
AFTER INSERT ON P2P
    FOR EACH ROW EXECUTE FUNCTION fnc_trg_update_transferred_points();

-- ----------------------------------checks--------------------------------------------- --
-- CALL p2p_check_add('snake', 'horse', 'task_5', 'Start', '22:09:00'); --new
-- CALL p2p_check_add('dog', 'raven', 'task_1', 'Start', '23:09:00'); --second
-- CALL p2p_check_add('dog', 'raven', 'task_1', 'Success', '23:10:00'); --second
-- CALL p2p_check_add('dog', 'raven', 'task_4', 'Start', '23:45:00'); --third
-- CALL p2p_check_add('snake', 'cat', 'task_2', 'Start', '22:09:00'); --
-- DELETE FROM p2p WHERE id = (SELECT COALESCE(MAX(id), 0) FROM p2p);
-- DELETE FROM checks WHERE id = (SELECT COALESCE(MAX(id), 0) FROM checks);
-- DELETE FROM transferred_points WHERE id = (SELECT COALESCE(MAX(id), 0) FROM transferred_points);


-- --------------------------------triger check add XP ---------------------------------- --

DROP FUNCTION IF EXISTS fnc_check_correct_before_insert_xp() CASCADE;

CREATE OR REPLACE FUNCTION fnc_check_correct_before_insert_xp() RETURNS TRIGGER AS $trg_check_correct_before_insert_xp$
    BEGIN
        IF ((SELECT max_xp FROM checks
            JOIN tasks ON checks.task = tasks.title
            WHERE NEW.check_id = checks.id) < NEW.xp_amount OR
            (SELECT state FROM p2p
             WHERE NEW.check_id = p2p.check_id AND p2p.state IN ('Success', 'Failure')) = 'Failure' OR
            (SELECT state FROM verter
             WHERE NEW.check_id = verter.check_id AND verter.state = 'Failure') = 'Failure') THEN
                RAISE EXCEPTION 'The number of XP exceeds the maximum or the test result is failed';
        END IF;
    RETURN (NEW.id, NEW.check_id, NEW.xp_amount);
    END;
$trg_check_correct_before_insert_xp$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_correct_before_insert_xp
BEFORE INSERT ON XP
    FOR EACH ROW EXECUTE FUNCTION fnc_check_correct_before_insert_xp();


-- INSERT INTO xp (id, check_id, xp_amount)
-- VALUES (6, 7, 200);                                                        --success
-- CALL verter_check_add('dog', 'task_1', 'Start', '23:15:00');     --fail bc of verter fail
-- CALL verter_check_add('dog', 'task_1', 'Failure', '23:20:00');
-- INSERT INTO xp (id, check_id, xp_amount)
-- VALUES (7, 10, 200);                                                       
-- ----------func 1---------- --
CREATE OR REPLACE FUNCTION hr_tranferred_ponts()
RETURNS TABLE (peer1 varchar, peer2 varchar, points_amount integer)
AS $$ (SELECT checking_peer, checked_peer, SUM(points_amount)
	   FROM (SELECT
			CASE WHEN checking_peer > checked_peer THEN checking_peer ELSE checked_peer END AS checking_peer,
			CASE WHEN checking_peer > checked_peer THEN checked_peer ELSE checking_peer END AS checked_peer,
			CASE WHEN checking_peer > checked_peer THEN points_amount ELSE -points_amount END AS points_amount
			FROM transferred_points) AS buf_table
	   GROUP BY 1, 2
); $$ LANGUAGE sql;

-- ----------func_1_checks---------- --
-- SELECT * FROM hr_tranferred_ponts();

-- ----------func_2---------- --
CREATE OR REPLACE FUNCTION completed_tasks()
RETURNS TABLE (peer varchar, task varchar, xp integer)
AS $$ (SELECT checks.peer, checks.task, xp.xp_amount
	   FROM checks 
	   JOIN xp ON checks.id=xp.check_id
	   JOIN p2p ON checks.id=p2p.check_id
	   FULL JOIN verter ON checks.id=verter.check_id
	   WHERE p2p.state='Success' AND (verter.state='Success' OR verter.state IS NULL)
);
$$ LANGUAGE sql;

-- ----------func_2_checks---------- --
-- SELECT * FROM completed_tasks();

-- ----------func_3---------- --
CREATE OR REPLACE FUNCTION all_day_in_campus(selected_date date)
RETURNS TABLE (name varchar)
AS $$ (SELECT peer 
	   FROM (SELECT time_tracking.peer 
	  		 FROM time_tracking
	  		 JOIN (SELECT peer FROM time_tracking
	  		 	   WHERE date=selected_date
	  		 	   GROUP BY peer
	  		 	   HAVING COUNT(peer) < 3) AS right_names
	  		 ON time_tracking.peer=right_names.peer
	  		 WHERE time_tracking.date=selected_date AND ((time_tracking.state=1 AND time_tracking.time<'12:00:00') OR (time_tracking.state=2 AND time_tracking.time>'18:00:00'))) AS names_list
GROUP by peer
HAVING COUNT(peer)=2
);
$$ LANGUAGE sql;

-- ----------func_3_checks---------- --	   
-- SELECT * FROM all_day_in_campus('2024-01-16');

-- ----------func_4---------- --
CREATE OR REPLACE FUNCTION quantity_change_point()
RETURNS TABLE (peer varchar, points_change int)
AS $$ (SELECT plus_point.checking_peer, plus_point.count-minus_point.count
	  FROM (SELECT checking_peer, COUNT(points_amount) FROM transferred_points
	  	   GROUP BY checking_peer) AS plus_point
	  FULL JOIN (SELECT checked_peer, COUNT(points_amount) FROM transferred_points
	  	   GROUP BY checked_peer) AS minus_point
	  ON plus_point.checking_peer=minus_point.checked_peer
);
$$ LANGUAGE sql;

-- ----------func_4_checks---------- --
-- SELECT * FROM quantity_change_point();

-- ----------func_5---------- --
CREATE OR REPLACE FUNCTION peer_points_change()
RETURNS TABLE (peer varchar, points_change integer)
AS $$ (SELECT peer, SUM(points_change)
	   FROM (SELECT peer1 AS peer, SUM(points_amount) AS points_change
			FROM hr_tranferred_ponts()
			GROUP BY peer1
			UNION
			SELECT peer2 AS peer, -SUM(points_amount) AS points_change
			FROM hr_tranferred_ponts()
			GROUP BY peer2) AS buf_table
	   GROUP BY 1
	   ORDER BY 2
);
$$ LANGUAGE sql;

-- ----------func_5_checks---------- --
-- SELECT * FROM peer_points_change();

-- ----------func_6---------- --
CREATE OR REPLACE FUNCTION most_popular_day_check()
    RETURNS TABLE (day date, task varchar)
AS $$ (SELECT count_group.date, count_group.task
       FROM (SELECT date, task, COUNT(task) FROM checks
             GROUP BY date, task
             ORDER BY date) AS count_group
                JOIN (SELECT date, max(count)
                      FROM (SELECT date, task, COUNT(task) AS count FROM checks
                            GROUP BY date, task
                            ORDER BY date) AS day_max_count
                      GROUP BY date) AS day_max_count
                     ON count_group.date=day_max_count.date
       WHERE count_group.count=day_max_count.max
       ORDER BY 1
      );
$$ LANGUAGE sql;

-- ----------func_6_checks---------- --
-- SELECT * FROM most_popular_day_check();

-- ----------func_7---------- --
CREATE OR REPLACE FUNCTION finished_block(block varchar)
RETURNS TABLE (name varchar, date date)
AS $$ (SELECT buf_table.peer, buf_table_date.date
	   FROM (SELECT checks.peer, COUNT(checks.task) FROM checks
	 		JOIN p2p ON p2p.check_id=checks.id
	 		FULL JOIN verter ON verter.check_id=checks.id
	 		WHERE (checks.task LIKE block || 'O%' OR checks.task LIKE block || '1%'
	 		OR checks.task LIKE block || '2%' OR checks.task LIKE block || '3%'
	 		OR checks.task LIKE block || '4%' OR checks.task LIKE block || '5%')
	 		AND (p2p.state='Success' AND (verter.state='Success' OR verter.state IS NULL))
	 		GROUP BY checks.peer) AS buf_table
	   JOIN (SELECT peer, date FROM checks
	 		WHERE (checks.task LIKE block || 'O%' OR checks.task LIKE block || '1%'
	 		OR checks.task LIKE block || '2%' OR checks.task LIKE block || '3%'
	 		OR checks.task LIKE block || '4%' OR checks.task LIKE block || '5%')
	 		ORDER BY date DESC) AS buf_table_date ON buf_table_date.peer=buf_table.peer
	   WHERE buf_table.count=(SELECT COUNT(title) FROM tasks
					  		 WHERE (title LIKE block || 'O%' OR title LIKE block || '1%'
					  		 OR title LIKE block || '2%' OR title LIKE block || '3%'
					  		 OR title LIKE block || '4%' OR title LIKE block || '5%'))
	   AND buf_table_date.peer=buf_table.peer
	   LIMIT 1
);
$$ LANGUAGE sql;

-- ----------func_7_checks---------- --
-- SELECT * FROM finished_block('CPP');
-- SELECT * FROM finished_block('C');
-- SELECT * FROM finished_block('D');

-- ----------func_8---------- --
CREATE OR REPLACE FUNCTION best_reviewer_for_everbody()
RETURNS TABLE (peer varchar, recommended_peer varchar) AS
$$ (SELECT buf_table_1.peer1 AS peer, buf_table_1.peer2 AS recommended_peer
	FROM (SELECT friends.peer1, recommendations.recommended_peer AS peer2, count(recommendations.recommended_peer)
		FROM friends
		FULL JOIN recommendations ON friends.peer2=recommendations.peer
		WHERE friends.peer1!=recommendations.recommended_peer
		GROUP BY 1, 2
		ORDER BY 1, 3 DESC) AS buf_table_1
	JOIN (SELECT buf_table.peer1 AS peer, MAX(buf_table.count) AS max_recom
		FROM(SELECT friends.peer1, count(recommendations.recommended_peer)
			FROM friends
			FULL JOIN recommendations ON friends.peer2=recommendations.peer
			WHERE friends.peer1!=recommendations.recommended_peer
			GROUP BY 1
			ORDER BY 1, 2 DESC) AS buf_table
		GROUP BY 1) AS buf_table_2 ON buf_table_2.peer=buf_table_1.peer1
	WHERE buf_table_2.max_recom=buf_table_1.count
);
$$ LANGUAGE sql;
-- ----------func_8_checks---------- --
-- SELECT * FROM best_reviewer_for_everbody();



-- ----------func_9---------- --
CREATE OR REPLACE FUNCTION who_started_blocks()
RETURNS TABLE(started_cpp_block numeric, started_c_block numeric,
			 started_d_block numeric, didnt_start_any_block numeric) AS 
$$ (SELECT
	ROUND((SELECT CAST(COUNT(*) AS numeric)
	 	  FROM (SELECT peer FROM checks
	 	  WHERE task LIKE 'CPP' || 'O%' OR task LIKE 'CPP' || '1%'
	 	  GROUP BY 1) AS cpp) 
		  / (SELECT CAST(COUNT(nickname) AS numeric) FROM peers) 
		  * 100, 2) AS started_cpp_block,
	ROUND((SELECT CAST(COUNT(*) AS numeric)
	 	  FROM (SELECT peer FROM checks
	 	  WHERE task LIKE 'C' || 'O%' OR task LIKE 'C' || '1%'
	 	  GROUP BY 1) AS c) 
		  / (SELECT CAST(COUNT(nickname) AS numeric) FROM peers) 
		  * 100, 2) AS started_c_block,
	ROUND((SELECT CAST(COUNT(*) AS numeric)
	 	  FROM (SELECT peer FROM checks
	 	  WHERE task LIKE 'D' || 'O%' OR task LIKE 'D' || '1%'
	 	  GROUP BY 1) AS d) 
		  / (SELECT CAST(COUNT(nickname) AS numeric) FROM peers) 
		  * 100, 2) AS started_d_block,
	ROUND((SELECT CAST(COUNT(*) AS numeric)
	 	  FROM (SELECT nickname FROM peers
			   EXCEPT
			   SELECT peer FROM checks
	 	  ) AS nothing) 
		  / (SELECT CAST(COUNT(nickname) AS numeric) FROM peers) 
		  * 100, 2) AS didnt_start_any_block);
$$ LANGUAGE sql;

-- ----------func_9_checks---------- --
-- SELECT * FROM who_started_blocks();

-- ----------func_10---------- --
CREATE OR REPLACE FUNCTION birthday_checks()
RETURNS TABLE (successful_checks numeric, unsuccessful_checks numeric)
AS $$ 
DECLARE 
	total_peers numeric;
BEGIN
	SELECT COUNT(nickname) INTO total_peers
	FROM peers;
RETURN QUERY
	SELECT 
		ROUND(((SELECT COUNT(checks.peer) AS count FROM checks
		   JOIN peers ON peers.nickname=checks.peer
		   JOIN p2p ON checks.id=p2p.check_id
		   FULL JOIN verter ON checks.id=verter.check_id
		   WHERE to_char(checks.date, 'MM-DD')=to_char(peers.birthday, 'MM-DD')
		   AND p2p.state='Success' AND (verter.state='Success' OR verter.state IS NULL)) / total_peers * 100), 2) AS successful_checks,
		ROUND(((SELECT COUNT(checks.peer) AS count FROM checks
		   JOIN peers ON peers.nickname=checks.peer
		   JOIN p2p ON checks.id=p2p.check_id
		   FULL JOIN verter ON checks.id=verter.check_id
		   WHERE to_char(checks.date, 'MM-DD')=to_char(peers.birthday, 'MM-DD')
		   AND ((p2p.state='Success' AND verter.state='Failure')
		   OR (p2p.state='Failure'))) / total_peers * 100), 2) AS unsuccessful_checks;
END
$$ LANGUAGE plpgsql;

-- ----------func_10_checks---------- --
-- SELECT * FROM birthday_checks();

-- ----------func_11---------- --
CREATE OR REPLACE FUNCTION success_check(arg_peer varchar, arg_task varchar)
RETURNS bool AS
$$
DECLARE 
	exit_code bool;
BEGIN
	IF (SELECT COUNT(checks.peer) FROM checks 
	   JOIN p2p ON checks.id=p2p.check_id
	   FULL JOIN verter ON checks.id=verter.check_id
	   WHERE checks.peer=arg_peer AND checks.task=arg_task
	   AND p2p.state='Success' AND (verter.state='Success' OR verter.state IS NULL)) > 0
	THEN exit_code=1;
	ELSE exit_code=0;
	END IF;
RETURN exit_code;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION peers_2passed_and_1failure_tasks(task1 varchar, task2 varchar, task3 varchar)
RETURNS TABLE (peer varchar)
AS $$ (SELECT peer FROM checks
	   WHERE success_check(peer, task1) IS TRUE
	   AND success_check(peer, task2) IS TRUE
	   AND success_check(peer, task3) IS FALSE
	   GROUP BY peer
);
$$ LANGUAGE sql;

-- ----------func_11_checks---------- --
-- SELECT * FROM peers_2passed_and_1failure_tasks('CPP2_s21_containers', 'CPP3_SmartCalc_v2', 'CPP4_3DViewer_v2');
-- SELECT * FROM peers_2passed_and_1failure_tasks('DO3_Simple_Docker', 'DO4_CICD', 'CPP1_s21_matrix');

-- ----------func_12---------- --
CREATE OR REPLACE FUNCTION previous_tasks() 
RETURNS TABLE(task varchar, prev_count integer) AS $$
BEGIN
	RETURN QUERY
	WITH RECURSIVE task_CTE AS (
		SELECT title, 0 AS prev_count
		FROM tasks
		WHERE parent_task IS NULL

		UNION ALL

		SELECT t.title, task_CTE.prev_count + 1
		FROM tasks t
		INNER JOIN task_CTE ON t.parent_task = task_CTE.title
	)
	SELECT * FROM task_CTE;
END;
$$ LANGUAGE plpgsql;

-- ----------func_12_checks---------- --
-- SELECT * FROM previous_tasks();

-- ----------func_13---------- --
CREATE OR REPLACE FUNCTION lucky_days_for_checks(n int)
RETURNS TABLE (lucky_day date)
AS $$ (SELECT date
      FROM (SELECT *
      	FROM checks
      	JOIN p2p ON checks.id = p2p.check_id
      	LEFT JOIN verter ON checks.id = verter.check_id
      	JOIN tasks ON checks.task = tasks.title
      	JOIN xp ON checks.id = xp.check_id
      	WHERE (p2p.state = 'Success')
      	AND (verter.state = 'Success' OR verter.state IS NULL)) AS erb
      WHERE xp_amount >= max_xp * 0.8
      GROUP BY date
      HAVING COUNT(date) >= n
);
$$ LANGUAGE sql;
-- ----------func_13_checks---------- --
-- SELECT * FROM lucky_days_for_checks(2);

-- ----------func_14---------- --
CREATE OR REPLACE FUNCTION most_experience()
RETURNS TABLE (peer varchar, xp numeric)
AS $$ (SELECT checks.peer, SUM(xp.xp_amount)
      FROM checks
      INNER JOIN xp ON (xp.check_id = checks.id)
      GROUP BY 1
      ORDER BY 2 DESC
      LIMIT 1
);
$$ LANGUAGE sql;

-- ----------func_14_checks---------- --
-- SELECT * FROM most_experience();

-- ----------func_15---------- --
CREATE OR REPLACE FUNCTION early_arrivals_peers (arg_time time, N integer)
RETURNS TABLE (peer varchar)
AS $$ (SELECT peer FROM time_tracking 
	  WHERE time < arg_time
	  GROUP BY peer
	  HAVING COUNT(*) >= N
);
$$ LANGUAGE sql;

-- ----------func_15_checks---------- --
-- SELECT * FROM early_arrivals_peers('11:00:000', 2);

-- ----------func_16---------- --
CREATE OR REPLACE FUNCTION departed_peers(n integer, m integer)
RETURNS TABLE (peer varchar)
AS $$ 
DECLARE
	start_date date;
BEGIN
	start_date=(SELECT MAX(date) FROM time_tracking) - (n-1);
RETURN QUERY
	SELECT time_tracking.peer FROM time_tracking
	WHERE state=2
	AND time_tracking.date>=start_date
	GROUP BY 1
	HAVING COUNT(state) >= m;
END
$$ LANGUAGE plpgsql;

-- ----------func_16_checks---------- --
-- SELECT * FROM departed_peers(1, 2);
-- SELECT * FROM departed_peers(2, 2);

-- ----------func_17---------- --
CREATE OR REPLACE FUNCTION early_arrivals_on_month()
RETURNS TABLE (months char, early_entries numeric) AS
$$ (WITH all_entries AS (SELECT EXTRACT(MONTH FROM date) AS month, COUNT(*) AS counts
                 FROM time_tracking
                 JOIN peers ON time_tracking.peer = peers.nickname
                 WHERE time_tracking.state = '1'
                 GROUP BY month),
         early_entries AS (SELECT EXTRACT(MONTH FROM date) as month, count(*) AS counts
                 FROM time_tracking
                 JOIN peers ON peers.nickname = time_tracking.peer
                 WHERE time_tracking.Time < '12:00'
                 AND time_tracking.state = '1'
                 GROUP BY month)
    SELECT to_char(to_date(all_entries.month::text, 'MM'), 'Month') AS months,
           ROUND((CAST(sum(early_entries.counts) AS numeric) * 100) / CAST(sum(all_entries.counts) AS numeric), 0) AS early_entries
    FROM all_entries
    JOIN early_entries ON all_entries.month = early_entries.month
    GROUP BY all_entries.month
    ORDER BY all_entries.month
);
$$ LANGUAGE sql;

-- ----------func_17_checks---------- --
-- SELECT * FROM early_arrivals_on_month();
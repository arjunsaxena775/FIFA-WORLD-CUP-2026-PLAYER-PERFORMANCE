select * from fifa_world_cup_2026_player_performance

---Q1. Team Goal Breakdown ---
---Write a query to display each team, the total number of goals scored by their players,
---and their average passing accuracy percentage (calculated as successful_passes / total_passes * 100).
---Filter out any rows where total_passes is 0 to avoid division errors.---
SELECT 
    team,
    SUM(goals) AS total_goals,
    AVG(CAST(successful_passes AS FLOAT) / total_passes * 100) AS avg_pass_accuracy
FROM fifa_world_cup_2026_player_performance
WHERE total_passes > 0
GROUP BY team;

---Q2. High-Valued Strikers---
---Find all players listed as 'Forward' whose market_value_eur is strictly higher than the average
---market value of all Forwards in the dataset. Return their player_name, team, and market_value_eur.---
SELECT 
    player_name,
    team,
    market_value_eur
FROM fifa_world_cup_2026_player_performance
WHERE position = 'Forward'
  AND market_value_eur > (
      SELECT AVG(CAST(market_value_eur AS BIGINT))
      FROM fifa_world_cup_2026_player_performance
      WHERE position = 'Forward'
  );

  ---Q3. Top Scorer per Team (Window Function)---
  ---Write a query using a window function (DENSE_RANK() or ROW_NUMBER()) to list the top scorer (goals)
  ---for each team. If there is a tie, return all tied players.---
  ---Expected Output Columns: team, player_name, goals, rank---
  WITH RankedScorers AS (
    SELECT 
        team,
        player_name,
        goals,
        DENSE_RANK() OVER (PARTITION BY team ORDER BY goals DESC) AS rank
    FROM fifa_world_cup_2026_player_performance
)
SELECT 
    team,
    player_name,
    goals,
    rank
FROM RankedScorers
WHERE rank = 1;

---Q4. Discipline and Performance Summary--
---Find players who have received at least 1 yellow card or red card (yellow_cards > 0 OR red_cards > 0), 
---but still maintained an above-average player_rating compared to all players in their respective position.---
WITH PositionAverages AS (
    SELECT 
        player_name,
        team,
        position,
        yellow_cards,
        red_cards,
        player_rating,
        AVG(player_rating) OVER (PARTITION BY position) AS avg_position_rating
    FROM fifa_world_cup_2026_player_performance
)
SELECT 
    player_name,
    team,
    position,
    yellow_cards,
    red_cards,
    ROUND(player_rating, 2) AS player_rating,
    ROUND(avg_position_rating, 2) AS avg_position_rating
FROM PositionAverages
WHERE (yellow_cards > 0 OR red_cards > 0)
  AND player_rating > avg_position_rating;

  ---Q5. Player Work-Rate Efficiency Matrix---
  ---Write a query to find the top 3 players in each position who cover the most distance per 90 minutes / match, 
  ---provided they have played and scored at least 1 goal. Order the final output by position and rank.---
  WITH RankedDistance AS (
    SELECT 
        position,
        player_name,
        team,
        goals,
        distance_covered_km, -- Or distance_km / distance_per_90 based on exact column name
        DENSE_RANK() OVER (
            PARTITION BY position 
            ORDER BY distance_covered_km DESC
        ) AS pos_rank
    FROM fifa_world_cup_2026_player_performance
    WHERE goals >= 1
)
SELECT 
    position,
    player_name,
    team,
    goals,
    distance_covered_km,
    pos_rank
FROM RankedDistance
WHERE pos_rank <= 3
ORDER BY position, pos_rank;

---Q6. Cumulative Metrics & Subqueries---
---For each team, calculate the running cumulative total of goals scored across the dataset (or ordered by player_id). 
---Additionally, display what percentage of the team's total goals were scored by each individual player.---
WITH DistinctPlayers AS (
    SELECT DISTINCT
        team,
        player_id,
        player_name,
        goals
    FROM fifa_world_cup_2026_player_performance
),
TeamTotals AS (
    SELECT 
        team,
        player_id,
        player_name,
        goals,
        SUM(goals) OVER (PARTITION BY team) AS total_team_goals,
        SUM(goals) OVER (
            PARTITION BY team 
            ORDER BY player_id 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_team_goals
    FROM DistinctPlayers
)
SELECT 
    team,
    player_id,
    player_name,
    goals,
    running_team_goals,
    total_team_goals,
    ROUND((CAST(goals AS FLOAT) / NULLIF(total_team_goals, 0)) * 100, 2) AS pct_of_team_goals
FROM TeamTotals
ORDER BY team, player_id;

---7. Identify high-performing, late-game players by analyzing physical effort against performance metrics.
---Write a query to return all players who covered more distance (distance_covered_km) than the overall average across the entire dataset,
---while simultaneously maintaining a clutch_performance_score above 8.00, ordering the final results from highest to lowest clutch score.---
SELECT 
    player_id,
    team,
    distance_covered_km,
    stamina_score,
    clutch_performance_score
FROM fifa_world_cup_2026_player_performance
WHERE distance_covered_km > (
    -- Subquery to calculate the dataset's overall average distance
    SELECT AVG(distance_covered_km) 
    FROM fifa_world_cup_2026_player_performance
)
AND clutch_performance_score > 8.00
ORDER BY clutch_performance_score DESC;

---8. Perform a tournament-wide value and performance tiering analysis using dynamic window quartiles. Write a query that divides all players
---into four performance quartiles based on their tournament_rating using NTILE(4), and then calculates the average market_value_eur and total goals
---for each quartile group to analyze whether market values align with high performance on the field.---
WITH PlayerQuartiles AS (
    SELECT 
        player_id,
        tournament_rating,
        market_value_eur,
        goals,
        -- Divide players into 4 equal groups based on performance rating (4 = top performance)
        NTILE(4) OVER (ORDER BY tournament_rating ASC) AS performance_quartile
    FROM fifa_world_cup_2026_player_performance
)
SELECT 
    performance_quartile,
    MIN(tournament_rating) AS min_rating_in_tier,
    MAX(tournament_rating) AS max_rating_in_tier,
    COUNT(player_id) AS total_players,
    ROUND(AVG(market_value_eur), 2) AS avg_market_value_eur,
    SUM(goals) AS total_goals,
    ROUND(AVG(CAST(goals AS DECIMAL(10, 2))), 2) AS avg_goals_per_player
FROM PlayerQuartiles
GROUP BY performance_quartile
ORDER BY performance_quartile DESC;

---9. Analyze team discipline risk using window ranking functions to identify top offenders. Write a query using a Common Table 
---Expression (CTE) to calculate total discipline events (the sum of yellow_cards and red_cards)and total fouls for every player, and
---then use DENSE_RANK() partitioned by team to display only the top two highest-risk players per team based on their foul-to-card volume.
WITH PlayerDiscipline AS (
    SELECT 
        team,
        player_id,
        fouls_committed,
        yellow_cards,
        red_cards,
        -- 1. Cast BIT columns to INT before adding them
        (CAST(yellow_cards AS INT) + CAST(red_cards AS INT)) AS total_cards,
        
        -- 2. Rank players using the cast values
        DENSE_RANK() OVER (
            PARTITION BY team 
            ORDER BY (CAST(yellow_cards AS INT) + CAST(red_cards AS INT)) DESC, 
                     fouls_committed DESC
        ) AS discipline_rank
    FROM fifa_world_cup_2026_player_performance
)
SELECT 
    team,
    player_id,
    fouls_committed,
    yellow_cards,
    red_cards,
    total_cards,
    discipline_rank
FROM PlayerDiscipline
WHERE discipline_rank <= 2
ORDER BY team, discipline_rank;

---10. Write a query to evaluate player match impact by comparing each individual player's performance against their team's standard. Specifically,
--display each player's player_rating alongside the calculated average rating for their team within that same tournament_stage, and include a computed 
---column that shows the exact difference between the player's rating and their team's average.---
SELECT 
    team,
    tournament_stage,
    player_id,
    player_rating,
    -- 1. Calculate average rating for the player's team in the specific tournament stage
    ROUND(
        AVG(player_rating) OVER (
            PARTITION BY team, tournament_stage
        ), 2
    ) AS team_stage_avg_rating,
    
    -- 2. Calculate the exact difference between the player's rating and the team stage average
    ROUND(
        player_rating - AVG(player_rating) OVER (
            PARTITION BY team, tournament_stage
        ), 2
    ) AS rating_diff_from_team_avg
FROM fifa_world_cup_2026_player_performance
ORDER BY team, tournament_stage, rating_diff_from_team_avg DESC;
IF EXISTS (
		SELECT *
		FROM sys.objects
		WHERE object_id = OBJECT_ID(N'[dbo].[Calendar]')
			AND type IN (N'U')
		)
	DROP TABLE [dbo].[Calendar]

	IF OBJECT_ID('tempdb.dbo.#bh', 'U') IS NOT NULL
	DROP TABLE #bh;



IF OBJECT_ID('tempdb.dbo.#dim', 'U') IS NOT NULL
	DROP TABLE #dim;


DECLARE @StartDate DATE = '20100101'
	,@NumberOfYears INT = 50;

-- Set and establish the region and date format

SET DATEFIRST 7;
SET DATEFORMAT mdy;
SET LANGUAGE US_ENGLISH;

DECLARE @CutoffDate DATE = DATEADD(YEAR, @NumberOfYears, @StartDate);

-- holding table for intermediate calculations:
CREATE TABLE #dim (
	[date] DATE PRIMARY KEY
	,[day] AS DATEPART(DAY, [date])
	,[month] AS DATEPART(MONTH, [date])
	,FirstOfMonth AS CONVERT(DATE, DATEADD(MONTH, DATEDIFF(MONTH, 0, [date]), 0))
	,[MonthName] AS DATENAME(MONTH, [date])
	,[week] AS DATEPART(WEEK, [date])
	,[ISOweek] AS DATEPART(ISO_WEEK, [date])
	,[DayOfWeek] AS DATEPART(WEEKDAY, [date])
	,[quarter] AS DATEPART(QUARTER, [date])
	,[year] AS DATEPART(YEAR, [date])
	,FirstOfYear AS CONVERT(DATE, DATEADD(YEAR, DATEDIFF(YEAR, 0, [date]), 0))
	,Style112 AS CONVERT(CHAR(8), [date], 112)
	,Style101 AS CONVERT(CHAR(10), [date], 101)
	);

-- use the catalog views to generate as many rows as we need
INSERT #dim ([date])
SELECT d
FROM (
	SELECT d = DATEADD(DAY, rn - 1, @StartDate)
	FROM (
		SELECT TOP (DATEDIFF(DAY, @StartDate, @CutoffDate)) rn = ROW_NUMBER() OVER (
				ORDER BY s1.[object_id]
				)
		FROM sys.all_objects AS s1
		CROSS JOIN sys.all_objects AS s2
		ORDER BY s1.[object_id]
		) AS x
	) AS y;

CREATE TABLE dbo.Calendar (
	DateKey INT NOT NULL PRIMARY KEY
	,[Date] DATE NOT NULL
	,[Day] TINYINT NOT NULL
	,DaySuffix CHAR(2) NOT NULL
	,[Weekday] TINYINT NOT NULL
	,WeekDayName VARCHAR(10) NOT NULL
	,IsWorkday BIT NOT NULL
	,IsWeekend BIT NOT NULL
	,IsHoliday BIT NOT NULL
	,HolidayText VARCHAR(64) SPARSE
	,DOWInMonth TINYINT NOT NULL
	,[DayOfYear] SMALLINT NOT NULL
	,WeekOfMonth TINYINT NOT NULL
	,WeekOfYear TINYINT NOT NULL
	,ISOWeekOfYear TINYINT NOT NULL
	,[Month] TINYINT NOT NULL
	,[MonthName] VARCHAR(10) NOT NULL
	,[Quarter] TINYINT NOT NULL
	,QuarterName VARCHAR(6) NOT NULL
	,[Year] INT NOT NULL
	,MMYYYY CHAR(6) NOT NULL
	,MonthYear CHAR(7) NOT NULL
	,FirstDayOfMonth DATE NOT NULL
	,LastDayOfMonth DATE NOT NULL
	,FirstDayOfQuarter DATE NOT NULL
	,LastDayOfQuarter DATE NOT NULL
	,FirstDayOfYear DATE NOT NULL
	,LastDayOfYear DATE NOT NULL
	,FirstDayOfNextMonth DATE NOT NULL
	,FirstDayOfNextYear DATE NOT NULL
	);
GO

INSERT dbo.Calendar
WITH (TABLOCKX)
SELECT DateKey = CONVERT(INT, Style112)
	,[Date] = [date]
	,[Day] = CONVERT(TINYINT, [day])
	,DaySuffix = CONVERT(CHAR(2), CASE 
			WHEN [day] / 10 = 1
				THEN 'th'
			ELSE CASE RIGHT([day], 1)
					WHEN '1'
						THEN 'st'
					WHEN '2'
						THEN 'nd'
					WHEN '3'
						THEN 'rd'
					ELSE 'th'
					END
			END)
	,[Weekday] = CONVERT(TINYINT, [DayOfWeek])
	,[WeekDayName] = CONVERT(VARCHAR(10), DATENAME(WEEKDAY, [date]))
	,[IsWorkday] = CONVERT(BIT, 0)
	,[IsWeekend] = CONVERT(BIT, CASE 
			WHEN [DayOfWeek] IN (1, 7)
				THEN 1
			ELSE 0
			END)
	,[IsHoliday] = CONVERT(BIT, 0)
	,HolidayText = CONVERT(VARCHAR(64), NULL)
	,[DOWInMonth] = CONVERT(TINYINT, ROW_NUMBER() OVER (
			PARTITION BY FirstOfMonth
			,[DayOfWeek] ORDER BY [date]
			))
	,[DayOfYear] = CONVERT(SMALLINT, DATEPART(DAYOFYEAR, [date]))
	,WeekOfMonth = CONVERT(TINYINT, DENSE_RANK() OVER (
			PARTITION BY [year]
			,[month] ORDER BY [week]
			))
	,WeekOfYear = CONVERT(TINYINT, [week])
	,ISOWeekOfYear = CONVERT(TINYINT, ISOWeek)
	,[Month] = CONVERT(TINYINT, [month])
	,[MonthName] = CONVERT(VARCHAR(10), [MonthName])
	,[Quarter] = CONVERT(TINYINT, [quarter])
	,QuarterName = CONVERT(VARCHAR(6), CASE [quarter]
			WHEN 1
				THEN 'First'
			WHEN 2
				THEN 'Second'
			WHEN 3
				THEN 'Third'
			WHEN 4
				THEN 'Fourth'
			END)
	,[Year] = [year]
	,MMYYYY = CONVERT(CHAR(6), LEFT(Style101, 2) + LEFT(Style112, 4))
	,MonthYear = CONVERT(CHAR(7), LEFT([MonthName], 3) + LEFT(Style112, 4))
	,FirstDayOfMonth = FirstOfMonth
	,LastDayOfMonth = MAX([date]) OVER (
		PARTITION BY [year]
		,[month]
		)
	,FirstDayOfQuarter = MIN([date]) OVER (
		PARTITION BY [year]
		,[quarter]
		)
	,LastDayOfQuarter = MAX([date]) OVER (
		PARTITION BY [year]
		,[quarter]
		)
	,FirstDayOfYear = FirstOfYear
	,LastDayOfYear = MAX([date]) OVER (PARTITION BY [year])
	,FirstDayOfNextMonth = DATEADD(MONTH, 1, FirstOfMonth)
	,FirstDayOfNextYear = DATEADD(YEAR, 1, FirstOfYear)
FROM #dim
OPTION (MAXDOP 1);
	;

		/*Easter*/
WITH x
AS (
	SELECT d.[Date]
		,d.IsHoliday
		,d.HolidayText
		,h.HolidayName
	FROM dbo.Calendar AS d
	CROSS APPLY dbo.GetEasterHolidays(d.[Year]) AS h
	WHERE d.[Date] = h.[Date]
	)
UPDATE c
SET c.IsHoliday = 1
	,c.HolidayText = x.HolidayName
FROM x
INNER JOIN dbo.Calendar c ON x.DATE = c.DATE
	;


	/*Public & Bank Holidays*/
WITH x
AS (
	SELECT DateKey
		,[Date]
		,IsHoliday
		,HolidayText
		,FirstDayOfYear
		,DOWInMonth
		,[MonthName]
		,[WeekDayName]
		,[Day]
		,LastDOWInMonth = ROW_NUMBER() OVER (
			PARTITION BY FirstDayOfMonth
			,[Weekday] ORDER BY [Date] DESC
			)
	FROM dbo.Calendar
	)
UPDATE x
SET HolidayText = CASE 
		WHEN ([Date] = FirstDayOfYear)
			THEN 'New Year''s Day'
		WHEN (
				[MonthName] = 'December'
				AND [Day] = 25
				)
			THEN 'Christmas Day'
		WHEN (
				[MonthName] = 'December'
				AND [Day] = 25
				)
			THEN 'St Stephen''s Day'
		WHEN (
				[MonthName] = 'March'
				AND [Day] = 17
				)
			THEN 'St Patrick''s Day'
		WHEN (
				[MonthName] = 'March'
				AND [Day] = 18
				AND YEAR(x.[date]) = 2022
				)
			THEN 'Once Off Covid Bank Holiday'
		WHEN [MonthName] = 'February'
			AND [Day] = 1
			AND [WeekDayName] = 'Friday'
			AND YEAR(x.[date]) > 2022
			THEN 'St Brigid''s Day'
		END

SELECT min([day]) AS fstMon
	,[MonthName]
	,[Year]
	,[date]
	,isholiday
	,HolidayText
	,ROW_NUMBER() OVER (
		PARTITION BY [Year]
		,[MonthName] ORDER BY [Date]
		) rn
INTO #bh
FROM dbo.Calendar
WHERE WeekdayName = 'Monday'
	AND [month] IN (2, 6, 5, 8, 10)
GROUP BY [date]
	,isholiday
	,HolidayText
	,[MonthName]
	,[Year]

UPDATE c
SET isholiday = 1
	,Holidaytext = CASE 
		WHEN [month] = 5
			THEN 'May Day'
		WHEN [Month] = 2
			AND c.[year] > 2022
			THEN 'St Brigid''s Day'
		WHEN [month] = 6
			THEN 'June Bank Holiday'
		WHEN [month] = 8
			THEN 'August Bank Holiday'
		WHEN [month] = 10
			THEN 'October Bank Holiday'
		END
FROM dbo.Calendar c
INNER JOIN #bh bh ON c.[Date] = bh.[Date]
WHERE bh.rn = 1

/*St Brigids Day fix */
UPDATE c
SET IsHoliday = 0
	,HolidayText = NULL
FROM dbo.Calendar c
INNER JOIN (
	SELECT c1.WeekDayName
		,c1.HolidayText
		,c1.IsHoliday
		,c1.DATE UndoDate
	FROM dbo.Calendar c
	LEFT JOIN dbo.Calendar c1 ON C1.HolidayText = c.HolidayText
		AND c1.[year] = c.[year]
	WHERE c.[Year] > 2022
		AND c.[MonthName] = 'February'
		AND c.[Date] = c.[FirstDayOfMonth]
		AND c.WeekDayName != c1.WeekDayName
	) x ON c.[DATE] = x.undodate

UPDATE dbo.Calendar
SET IsHoliday = 1
WHERE HolidayText IS NOT NULL

UPDATE dbo.Calendar
SET IsWorkday = 1
WHERE [weekday] IN (2, 3, 4, 5, 6)
	AND IsHoliday = 0

DROP TABLE #bh

DROP TABLE #dim


-- First create the enum type
CREATE TYPE "ActivityType" AS ENUM ('created', 'voted', 'unvoted', 'edited', 'deleted', 'status_changed');

-- Add the new column that will use the enum (without NOT NULL initially)
ALTER TABLE "Activity" ADD COLUMN "new_type" "ActivityType";

-- Convert existing data to the new enum type
UPDATE "Activity" 
SET "new_type" = CASE 
    WHEN "type" = 'created' THEN 'created'::"ActivityType"
    WHEN "type" = 'voted' THEN 'voted'::"ActivityType"
    WHEN "type" = 'unvoted' THEN 'unvoted'::"ActivityType"
    WHEN "type" = 'edited' THEN 'edited'::"ActivityType"
    WHEN "type" = 'deleted' THEN 'deleted'::"ActivityType"
    WHEN "type" = 'status_changed' THEN 'status_changed'::"ActivityType"
    ELSE 'created'::"ActivityType"
END;

-- Verify no nulls exist in new_type
UPDATE "Activity" 
SET "new_type" = 'created'::"ActivityType"
WHERE "new_type" IS NULL;

-- Drop the old column
ALTER TABLE "Activity" DROP COLUMN "type";

-- Rename the new column to the original name
ALTER TABLE "Activity" RENAME COLUMN "new_type" TO "type";

-- Now that we're sure no nulls exist, add the NOT NULL constraint
ALTER TABLE "Activity" ALTER COLUMN "type" SET NOT NULL;

-- Add the deletedRequestTitle column
ALTER TABLE "Activity" ADD COLUMN "deletedRequestTitle" TEXT; 
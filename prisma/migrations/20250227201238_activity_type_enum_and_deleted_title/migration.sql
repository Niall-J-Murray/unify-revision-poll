/*
  Warnings:

  - Changed the type of `type` on the `Activity` table. No cast exists, the column would be dropped and recreated, which cannot be done if there is data, since the column is required.

*/
-- CreateEnum
CREATE TYPE "ActivityType" AS ENUM ('created', 'voted', 'unvoted', 'edited', 'deleted', 'status_changed');

-- DropForeignKey
ALTER TABLE "Activity" DROP CONSTRAINT "Activity_featureRequestId_fkey";

-- AlterTable
ALTER TABLE "Activity" ADD COLUMN     "deletedRequestTitle" TEXT,
DROP COLUMN "type",
ADD COLUMN     "type" "ActivityType" NOT NULL,
ALTER COLUMN "featureRequestId" DROP NOT NULL;

-- AddForeignKey
ALTER TABLE "Activity" ADD CONSTRAINT "Activity_featureRequestId_fkey" FOREIGN KEY ("featureRequestId") REFERENCES "feature_requests"("id") ON DELETE SET NULL ON UPDATE CASCADE;

/*
  Warnings:

  - A unique constraint covering the columns `[title,userId]` on the table `feature_requests` will be added. If there are existing duplicate values, this will fail.

*/
-- CreateIndex
CREATE UNIQUE INDEX "feature_requests_title_userId_key" ON "feature_requests"("title", "userId");

-- Azure SQL Database Schema for S3 Uploads
-- This table tracks the file metadata, folder structure and the URL

CREATE TABLE Files (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    FileName NVARCHAR(255) NOT NULL,
    FolderPath NVARCHAR(1000) NOT NULL, -- Logical folder structure path (e.g. "images/profile")
    S3Url NVARCHAR(2000) NOT NULL,      -- The final URL (or presigned URL) of the uploaded file
    ContentType NVARCHAR(100) NULL,
    UploadedAt DATETIME DEFAULT GETUTCDATE()
);

-- Optional: Create an index on FolderPath if you frequently query files by folder
CREATE INDEX IX_Files_FolderPath ON Files(FolderPath);

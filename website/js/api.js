// API Services and Utilities

const ApiService = {
  getApiUrl: () => localStorage.getItem('api_url') || '',
  setApiUrl: (url) => localStorage.setItem('api_url', url),

  // Compress image to WebP using Canvas API (mimics flutter_image_compress)
  compressImage: (file, quality = 0.75) => {
    return new Promise((resolve, reject) => {
      const img = new Image();
      const reader = new FileReader();

      reader.onload = (e) => {
        img.src = e.target.result;
      };

      img.onload = () => {
        const canvas = document.createElement('canvas');
        canvas.width = img.width;
        canvas.height = img.height;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(img, 0, 0);

        canvas.toBlob(
          (blob) => {
            if (blob) {
              resolve(blob);
            } else {
              reject(new Error('Canvas toBlob failed'));
            }
          },
          'image/webp',
          quality
        );
      };

      img.onerror = (err) => reject(err);
      reader.readAsDataURL(file);
    });
  },

  // Get presigned URL from Lambda
  getPresignedUrl: async (apiUrl, fileName, folderPath, contentType) => {
    const response = await fetch(apiUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        fileName,
        folderPath,
        contentType,
      }),
    });

    if (!response.ok) {
      throw new Error(`Failed to get presigned URL: ${response.statusText}`);
    }

    const data = await response.json();
    if (!data.presignedUrl) {
      throw new Error('Lambda response did not contain presignedUrl.');
    }

    return data.presignedUrl;
  },

  // Upload directly to S3
  uploadToS3: async (presignedUrl, fileBlob, contentType) => {
    const response = await fetch(presignedUrl, {
      method: 'PUT',
      headers: {
        'Content-Type': contentType,
      },
      body: fileBlob,
    });

    if (!response.ok) {
      throw new Error(`Failed to upload to S3: ${response.status} ${response.statusText}`);
    }
  },

  // Throttling state
  _isUploading: false,
  _isFetching: false,

  // Combined upload flow
  uploadFile: async (apiUrl, file, folderPath, customFileName) => {
    if (ApiService._isUploading) {
      throw new Error("An upload is already in progress. Please wait.");
    }
    
    try {
      ApiService._isUploading = true;
      let fileName = customFileName || file.name;
      let mimeType = file.type || 'application/octet-stream';
      let fileBlob = file;

      // Compress if it's an image
      if (mimeType.startsWith('image/')) {
        fileBlob = await ApiService.compressImage(file, 0.75);
        
        // Update extension to .webp
        const lastDot = fileName.lastIndexOf('.');
        if (lastDot !== -1) {
          fileName = fileName.substring(0, lastDot) + '.webp';
        } else {
          fileName += '.webp';
        }
        mimeType = 'image/webp';
      }

      const presignedUrl = await ApiService.getPresignedUrl(apiUrl, fileName, folderPath, mimeType);
      await ApiService.uploadToS3(presignedUrl, fileBlob, mimeType);
    } finally {
      ApiService._isUploading = false;
    }
  },

  // Fetch all uploaded files (with caching and delta sync)
  fetchUploadedFiles: async (apiUrl, forceRefresh = false) => {
    if (ApiService._isFetching) {
      throw new Error("A fetch request is already in progress. Please wait.");
    }

    try {
      ApiService._isFetching = true;
      let cachedData = [];
      let lastSync = null;

      if (!forceRefresh) {
        const cacheString = localStorage.getItem('gallery_cache');
        if (cacheString) {
          cachedData = JSON.parse(cacheString);
        }
        lastSync = localStorage.getItem('gallery_last_sync');
      } else {
        localStorage.removeItem('gallery_cache');
        localStorage.removeItem('gallery_last_sync');
      }

      const headers = {};
      if (lastSync) {
        headers['last-sync'] = lastSync;
      }

      const response = await fetch(apiUrl, { headers });
      if (!response.ok) {
        throw new Error(`Failed to fetch photos: ${response.status}`);
      }
      
      const newItems = await response.json();
      
      if (newItems.length > 0) {
        // Merge new items into cache
        const itemMap = new Map();
        // Add existing items
        cachedData.forEach(item => {
          itemMap.set(item.folderPath + '/' + item.fileName, item);
        });
        
        // Add/Update new items (and remove soft-deleted ones)
        newItems.forEach(item => {
          const key = item.folderPath + '/' + item.fileName;
          if (item.isDeleted) {
            itemMap.delete(key);
          } else {
            itemMap.set(key, item);
          }
        });
        
        cachedData = Array.from(itemMap.values());
        // Sort by uploadedAt desc
        cachedData.sort((a, b) => new Date(b.uploadedAt) - new Date(a.uploadedAt));
        
        localStorage.setItem('gallery_cache', JSON.stringify(cachedData));
        localStorage.setItem('gallery_last_sync', new Date().toISOString());
      }
      
      return cachedData;
    } finally {
      ApiService._isFetching = false;
    }
  },



  // Delete file
  deleteFile: async (apiUrl, fileName, folderPath) => {
    const response = await fetch(apiUrl, {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        fileName,
        folderPath,
      }),
    });

    if (!response.ok) {
      throw new Error('Failed to delete file');
    }
  }
};

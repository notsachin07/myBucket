document.addEventListener('DOMContentLoaded', () => {
  const apiUrl = ApiService.getApiUrl();
  if (!apiUrl) {
    window.location.href = 'index.html';
    return;
  }

  const galleryLoader = document.getElementById('gallery-loader');
  const galleryMessage = document.getElementById('gallery-message');
  const galleryContent = document.getElementById('gallery-content');
  const btnRefresh = document.getElementById('btn-refresh');

  // Modal Elements
  const detailModal = document.getElementById('image-detail-modal');
  const detailImg = document.getElementById('detail-img');
  const detailName = document.getElementById('detail-name');
  const detailFolder = document.getElementById('detail-folder');
  const detailDate = document.getElementById('detail-date');
  const detailType = document.getElementById('detail-type');
  const detailUrl = document.getElementById('detail-url');
  const btnCloseModal = document.getElementById('btn-close-modal');
  const btnDelete = document.getElementById('btn-delete');

  let currentSelectedFile = null;

  const formatDate = (dateStr) => {
    if (!dateStr) return 'Unknown';
    try {
      const date = new Date(dateStr);
      const pad = (n) => n.toString().padStart(2, '0');
      return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
    } catch (e) {
      return dateStr;
    }
  };

  const showMessage = (msg, isError = false) => {
    galleryLoader.style.display = 'none';
    galleryMessage.textContent = msg;
    galleryMessage.style.color = isError ? 'var(--danger-color)' : 'var(--text-muted)';
  };

  const loadGallery = async (forceRefresh = false) => {
    galleryContent.innerHTML = '';
    galleryLoader.style.display = 'inline-block';
    galleryMessage.textContent = 'Loading photos...';

    const startTime = Date.now();
    const timerInterval = setInterval(() => {
      const elapsed = Math.floor((Date.now() - startTime) / 1000);
      if (elapsed >= 1) {
        galleryMessage.textContent = `Waking up server (Cold Start)... Please wait (${elapsed}s)`;
      }
    }, 1000);

    try {
      const files = await ApiService.fetchUploadedFiles(apiUrl, forceRefresh);
      clearInterval(timerInterval);
      
      if (!files || files.length === 0) {
        showMessage('No photos uploaded yet.');
        return;
      }

      galleryLoader.style.display = 'none';
      galleryMessage.textContent = '';
      renderGallery(files);
    } catch (error) {
      clearInterval(timerInterval);
      showMessage(`Error: ${error.message}`, true);
    }
  };

  // Setup Intersection Observer for Lazy Presigning
  const observer = new IntersectionObserver((entries) => {
    const toPresign = [];
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        const img = entry.target;
        if (img.dataset.loaded !== 'true') {
          toPresign.push({ 
            img: img, 
            fileName: img.dataset.fileName, 
            folderPath: img.dataset.folderPath 
          });
          img.dataset.loaded = 'pending';
        }
      }
    });

    if (toPresign.length > 0) {
      const payload = toPresign.map(item => ({ fileName: item.fileName, folderPath: item.folderPath }));
      ApiService.fetchPresignedUrls(apiUrl, payload).then(urls => {
        toPresign.forEach(item => {
          const key = item.folderPath + '/' + item.fileName;
          if (urls[key]) {
            item.img.src = urls[key];
            item.img.dataset.loaded = 'true';
          } else {
            item.img.dataset.loaded = 'error';
          }
        });
      }).catch(console.error);
    }
  }, { rootMargin: "100px" });

  const renderGallery = (files) => {
    // Group by folder
    const grouped = {};
    files.forEach(file => {
      const folder = file.folderPath || 'Root';
      if (!grouped[folder]) grouped[folder] = [];
      grouped[folder].push(file);
    });

    // Sort folders alphabetically
    const folders = Object.keys(grouped).sort();

    folders.forEach(folder => {
      const filesInFolder = grouped[folder];
      
      const section = document.createElement('div');
      section.className = 'folder-section';
      
      const header = document.createElement('div');
      header.className = 'folder-header';
      header.innerHTML = `
        <svg viewBox="0 0 24 24"><path d="M10 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V8c0-1.1-.9-2-2-2h-8l-2-2z"/></svg>
        <span class="folder-title">${folder}</span>
        <span class="folder-count">${filesInFolder.length} files</span>
      `;

      const grid = document.createElement('div');
      grid.className = 'image-grid';
      
      // Expand/Collapse logic
      header.addEventListener('click', () => {
        grid.style.display = grid.style.display === 'none' ? 'grid' : 'none';
      });

      filesInFolder.forEach(file => {
        const item = document.createElement('div');
        item.className = 'grid-item';
        
        const img = document.createElement('img');
        // Lazy load: no src initially, just dataset
        img.dataset.fileName = file.fileName;
        img.dataset.folderPath = file.folderPath;
        img.dataset.loaded = 'false';
        img.alt = file.fileName;
        
        // Handle broken images
        img.onerror = () => {
          img.src = 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="%2394a3b8"><path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z"/></svg>';
          img.style.objectFit = 'none';
        };

        const label = document.createElement('div');
        label.className = 'grid-item-label';
        label.textContent = file.fileName;

        item.appendChild(img);
        item.appendChild(label);
        
        item.addEventListener('click', async () => {
          // If they click, make sure they have a presigned URL
          if (img.dataset.loaded !== 'true') {
            const urls = await ApiService.fetchPresignedUrls(apiUrl, [{ fileName: file.fileName, folderPath: file.folderPath }]);
            const key = file.folderPath + '/' + file.fileName;
            file.previewUrl = urls[key];
          } else {
            file.previewUrl = img.src;
          }
          openDetailModal(file);
        });
        
        grid.appendChild(item);
        
        // Observe image for lazy presigning
        observer.observe(img);
      });

      section.appendChild(header);
      section.appendChild(grid);
      galleryContent.appendChild(section);
    });
  };

  // Modal Logic
  const openDetailModal = (file) => {
    currentSelectedFile = file;
    detailImg.src = file.previewUrl || file.s3Url;
    detailName.textContent = file.fileName;
    detailFolder.textContent = file.folderPath;
    detailDate.textContent = formatDate(file.uploadedAt);
    
    const urlParts = file.s3Url.split('.');
    detailType.textContent = urlParts.length > 1 ? urlParts[urlParts.length - 1].toUpperCase() : 'UNKNOWN';
    
    detailUrl.textContent = file.s3Url;
    
    detailModal.classList.add('active');
  };

  const closeModal = () => {
    detailModal.classList.remove('active');
    currentSelectedFile = null;
  };

  detailUrl.addEventListener('click', () => {
    navigator.clipboard.writeText(detailUrl.textContent)
      .then(() => alert('URL copied to clipboard!'))
      .catch(err => console.error('Failed to copy: ', err));
  });

  btnCloseModal.addEventListener('click', closeModal);
  detailModal.addEventListener('click', (e) => {
    if (e.target === detailModal) closeModal();
  });

  btnDelete.addEventListener('click', async () => {
    if (!currentSelectedFile) return;
    
    if (confirm('Are you sure you want to delete this image from the server? This action cannot be undone.')) {
      btnDelete.disabled = true;
      try {
        await ApiService.deleteFile(apiUrl, currentSelectedFile.fileName, currentSelectedFile.folderPath);
        alert('Image deleted successfully');
        closeModal();
        loadGallery(true); // Force refresh after delete
      } catch (error) {
        alert(`Delete failed: ${error.message}`);
      } finally {
        btnDelete.disabled = false;
      }
    }
  });

  btnRefresh.addEventListener('click', () => loadGallery(true));

  // Initial Load (use cache if available)
  loadGallery(false);
});

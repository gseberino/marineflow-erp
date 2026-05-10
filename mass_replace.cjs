const fs = require('fs');
const path = require('path');

const directoryToSearch = path.join(__dirname, 'src');

const replacements = {
  'full_name_or_company_name': 'name',
  'supplier_name': 'name',
  'marina_name': 'name',
  'product_name': 'name',
  'service_name': 'name',
  'display_name': 'name',
  'product_name_snapshot': 'name_snapshot',
  'service_name_snapshot': 'name_snapshot',
  'contact_phone': 'phone',
  'contact_email': 'email'
};

function walkSync(dir, filelist = []) {
  const files = fs.readdirSync(dir);
  for (const file of files) {
    const dirFile = path.join(dir, file);
    const dirent = fs.statSync(dirFile);
    if (dirent.isDirectory()) {
      filelist = walkSync(dirFile, filelist);
    } else {
      if (dirFile.endsWith('.ts') || dirFile.endsWith('.tsx')) {
        filelist.push(dirFile);
      }
    }
  }
  return filelist;
}

const allFiles = walkSync(directoryToSearch);
let changedFilesCount = 0;

allFiles.forEach(file => {
  let content = fs.readFileSync(file, 'utf8');
  let hasChanges = false;
  
  for (const [oldVar, newVar] of Object.entries(replacements)) {
    // We use a global regex with word boundaries to ensure we only replace the exact variable
    const regex = new RegExp(`\\b${oldVar}\\b`, 'g');
    if (regex.test(content)) {
      content = content.replace(regex, newVar);
      hasChanges = true;
    }
  }
  
  if (hasChanges) {
    fs.writeFileSync(file, content, 'utf8');
    changedFilesCount++;
  }
});

console.log(`Substituição concluída! ${changedFilesCount} arquivos foram atualizados com sucesso.`);

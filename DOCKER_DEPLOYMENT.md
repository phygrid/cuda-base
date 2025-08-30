# Docker Build and Deploy Workflow

This repository uses GitHub Actions to automatically build and deploy the `phygrid/cuda-base` Docker image to Docker Hub with automatic version management.

## Setup Requirements

### 1. Docker Hub Secrets

Add these secrets to your GitHub repository settings:

- `DOCKER_USERNAME`: Your Docker Hub username
- `DOCKER_PASSWORD`: Your Docker Hub password or access token

### 2. Repository Permissions

Ensure the GitHub Actions workflow has permission to:
- Create releases
- Push tags
- Commit to the main branch

## Version Management

### VERSION File Approach
Version is tracked in the `VERSION` file containing semantic version (e.g., `1.0.0`).

### Automatic Versioning Behavior

#### Push to Main Branch
1. **If current version tag already exists**: Auto-increments patch version
   - `VERSION`: `1.0.0` → `1.0.1` (if `v1.0.0` tag exists)
2. **If current version tag doesn't exist**: Uses current version as-is
   - `VERSION`: `1.0.0` → `v1.0.0` (if `v1.0.0` tag doesn't exist)

#### Manual Version Bumps
Edit the `VERSION` file to bump major/minor versions:

```bash
# Bump minor version
echo "1.1.0" > VERSION
git add VERSION
git commit -m "Bump to v1.1.0"
git push origin main

# Bump major version  
echo "2.0.0" > VERSION
git add VERSION
git commit -m "Bump to v2.0.0"
git push origin main
```

### Workflow Triggers

#### Automatic Trigger
Push changes to main branch affecting:
- `Dockerfile`
- `VERSION` file  
- `.github/workflows/docker-build-deploy.yml`

#### Manual Trigger
Use GitHub's workflow dispatch feature:
1. Go to Actions → Build and Deploy Docker Image
2. Click "Run workflow"  
3. Click "Run workflow"

### Version Conflict Prevention
The workflow prevents building existing versions by:

1. **Docker Hub Check**: Verifies image doesn't exist on Docker Hub
2. **Tag Creation**: Creates git tags automatically
3. **Automatic Failure**: Stops build if version exists

## Built Images

Each successful build creates:

### Multi-Architecture Support
- `linux/amd64` (Intel/AMD)
- `linux/arm64` (ARM/Apple Silicon)

### Docker Hub Tags
- `phygrid/cuda-base:v1.0.0` (specific version)
- `phygrid/cuda-base:latest` (always latest version)

## Workflow Features

### Build Process
1. **Version Validation**: Ensures proper semantic versioning
2. **Conflict Detection**: Prevents duplicate versions
3. **Multi-Platform Build**: Supports AMD64 and ARM64
4. **Layer Caching**: Uses GitHub Actions cache for faster builds
5. **Automatic Tagging**: Creates git tags for manual dispatches

### Post-Build Actions
1. **Dockerfile Update**: Updates version label in Dockerfile
2. **GitHub Release**: Creates release with deployment details
3. **Build Notifications**: Success/failure status updates

### Self-Hosted Runner
Uses Dubai office self-hosted runners:
```yaml
runs-on:
  group: dubai-office
  labels: [self-hosted]
```

## Usage Examples

### Automatic Patch Increment
```bash
# Make changes to Dockerfile, commit and push
git add Dockerfile
git commit -m "Update base image dependencies"
git push origin main

# If v1.0.0 tag exists, workflow auto-increments to v1.0.1
# If v1.0.0 doesn't exist, uses v1.0.0
```

### Manual Version Bumps
```bash
# Bump minor version for new features
echo "1.1.0" > VERSION
git add VERSION  
git commit -m "Bump to v1.1.0 for new features"
git push origin main

# Bump major version for breaking changes
echo "2.0.0" > VERSION
git add VERSION
git commit -m "Bump to v2.0.0 for breaking changes"  
git push origin main
```

### Check Current Version
```bash
# Check VERSION file
cat VERSION

# List all git tags
git tag -l

# Check Docker Hub
docker pull phygrid/cuda-base:latest
docker images phygrid/cuda-base
```

### Manual Deployment
1. Navigate to repository → Actions
2. Select "Build and Deploy Docker Image"
3. Click "Run workflow"
4. Monitor build progress

## Troubleshooting

### Common Issues

**Version Already Exists**
```
Error: Docker image phygrid/cuda-base:v1.0.0 already exists on Docker Hub
```
**Solution**: Use a new version number

**Invalid Version Format**
```
Error: Invalid version format. Expected format: v1.0.0
```
**Solution**: Use semantic versioning format (vX.Y.Z)

**Docker Hub Authentication**
```
Error: unauthorized: authentication required
```
**Solution**: Check DOCKER_USERNAME and DOCKER_PASSWORD secrets

### Workflow Monitoring
- Check Actions tab for build status
- Review job logs for detailed information
- Monitor Docker Hub for successful pushes
- Verify GitHub releases are created

## Security Notes

- Docker Hub credentials stored as GitHub secrets
- Multi-stage build process for security
- Non-root user in Docker image
- Automated dependency updates via build process